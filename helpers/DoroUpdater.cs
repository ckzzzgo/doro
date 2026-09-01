// Dororo 更新助手。
//
// 为什么需要一个外部程序：运行中的 exe 不能覆盖自己，所以替换必须由另一个进程在主程序
// 退出之后完成。它同时也是升级失败时唯一还能把安装目录恢复原状的角色。
//
// 用法：
//   DoroUpdater.exe --zip <安装包路径> --target <安装目录> --pid <主进程 PID> [--no-relaunch]
//
// 关键设计：
//   1. 助手自身必须在被替换的目录之外运行（调用方负责先把它拷到临时目录），
//      否则替换到自己身上会失败。
//   2. 先把新版完整解压到安装目录旁边，全部就绪后才做切换。绝不边下边覆盖 ——
//      中途失败会留下一个半新半旧、根本打不开的安装目录。
//   3. 切换用目录改名（同一磁盘上近乎原子），而不是逐个文件复制。
//   4. 安装目录路径保持不变（只换内容、不改目录名），这样快捷方式与开机自启指向的
//      exe 路径依然有效。
//   5. 任何一步失败都回滚，并且在新目录确认可用之前绝不删除旧目录。
//   6. 全过程写日志到 %LOCALAPPDATA%\Dororo\update.log —— 必须在安装目录之外，
//      否则失败现场会连同目录一起被换掉，事后无从排查。
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Threading;

internal static class DoroUpdater
{
    // 新版内容至少要有这两个文件才认为解压结果可用
    private static readonly string[] RequiredFiles = { "dororo.exe", "dororo.pck" };

    private const int ParentWaitTimeoutMs = 30000;
    // 改名重试要给得足够宽：实测主进程退出后 0.5 秒目录就可改名，但真实更新时刚往同一个
    // 文件夹里解压完 208MB，杀毒软件的实时扫描会持续占用一段时间（用户装在 Downloads 下
    // 更明显）。原来 10 次 x 500ms = 5 秒不够，实机就是在这里失败的。
    /// 单个文件改名的重试。文件级占用比目录级短得多，几秒足够。
    private const int FileRetryCount = 12;
    private const int FileRetryDelayMs = 500;

    /// 整目录改名的重试窗口。刻意不长：这条路只是「顺利时更干净」的快捷方式
    /// （一次改名，原子性好），挡住了就交给逐文件替换 —— 后者已实测能在目录被
    /// 外部程序占住时照样完成。原来是 40 次 x 750ms = 30 秒，等于失败时先让用户
    /// 干瞪眼半分钟才开始真正有用的动作。
    private const int RenameRetryCount = 10;
    private const int RenameRetryDelayMs = 750;
    // 等「从安装目录运行的进程」全部退出。只等被告知的那一个 pid 不够：用户可能开了
    // 两个实例，或留有上一次的孤儿子进程，那些都锁着安装目录里的文件。
    private const int OccupantWaitMs = 20000;

    private static StreamWriter _log;

    private static int Main(string[] args)
    {
        string zip = null, target = null;
        int pid = -1;
        bool relaunch = true;

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--zip":    if (i + 1 < args.Length) zip = args[++i]; break;
                case "--target": if (i + 1 < args.Length) target = args[++i]; break;
                case "--pid":    if (i + 1 < args.Length) int.TryParse(args[++i], out pid); break;
                case "--no-relaunch": relaunch = false; break;
            }
        }

        OpenLog();
        Banner();
        Log("==== 更新助手启动 ====");
        Log("zip=" + zip);
        Log("target=" + target);
        Log("pid=" + pid + "  relaunch=" + relaunch);

        try
        {
            if (string.IsNullOrEmpty(zip) || string.IsNullOrEmpty(target))
            {
                Log("参数不全，退出");
                return Fail(2);
            }
            if (!File.Exists(zip))
            {
                Log("安装包不存在");
                return Fail(3);
            }
            if (!Directory.Exists(target))
            {
                Log("安装目录不存在");
                return Fail(4);
            }

            // 助手若位于将被替换的目录内，替换必然失败。调用方应先把它拷到别处。
            string self = Path.GetDirectoryName(Path.GetFullPath(
                Process.GetCurrentProcess().MainModule.FileName));
            if (IsSameOrInside(self, target))
            {
                Log("助手正运行于安装目录内(" + self + ")，无法替换自身所在目录");
                return Fail(5);
            }

            WaitForParent(pid);
            WaitForOccupants(target);

            string targetFull = Path.GetFullPath(target).TrimEnd(Path.DirectorySeparatorChar);
            string parent = Path.GetDirectoryName(targetFull);
            string staging = Path.Combine(parent, ".dororo_update_new");
            string backup = Path.Combine(parent, ".dororo_update_old");

            // 上一次失败可能留下残骸，先清干净，否则解压会混入旧文件
            SafeDeleteDir(staging);
            SafeDeleteDir(backup);

            Log("解压到 " + staging);
            Directory.CreateDirectory(staging);
            ZipFile.ExtractToDirectory(zip, staging);

            string content = FindContentRoot(staging);
            if (content == null)
            {
                Log("解压结果里找不到 " + string.Join(" / ", RequiredFiles) + "，判定安装包无效");
                SafeDeleteDir(staging);
                return Fail(6);
            }
            Log("新版内容位于 " + content);

            // ---- 切换。从这里开始出错必须回滚 ----
            //
            // 解压刚花了几秒，这几秒里情况可能已经变了 —— 最典型的是用户看到桌宠
            // 突然消失、以为崩了，又去双击了一次。所以改名前重新清一次场，
            // 而且在重试循环里持续清：只等一次是不够的。
            KillOccupants(targetFull, "改名前清场");

            Log("改名 " + targetFull + " -> " + backup);
            if (!TryMove(targetFull, backup, i => { if (i % 4 == 3) KillOccupants(targetFull, "重试中发现新的占用"); }))
            {
                // 整个目录改名要求目录本身和里面每个文件都没有被打开，一个都不行。
                // 实测有外部程序（杀软扫刚下载的安装包、或资源管理器开着那个文件夹）
                // 会短暂占住，一次持续了 30 秒以上，重试窗口再长也只是碰运气。
                //
                // 逐文件替换的要求低得多：只需要那一个文件此刻可动，而杀毒软件打开
                // 文件时通常带 FILE_SHARE_DELETE（否则它一扫描就会弄坏别的程序），
                // 所以扫描期间改名往往仍然能成。真正的安装程序也是这么做的。
                Log("整目录改名失败，改用逐文件替换");
                ReportBlockers(targetFull);
                if (!ReplaceFileByFile(content, targetFull))
                {
                    Log("逐文件替换也失败，未做任何改动");
                    SafeDeleteDir(staging);
                    RelaunchAfterFailure(targetFull, relaunch);
                    return Fail(7);
                }
                if (!HasRequiredFiles(targetFull))
                {
                    Log("逐文件替换后关键文件不齐");
                    SafeDeleteDir(staging);
                    RelaunchAfterFailure(targetFull, relaunch);
                    return Fail(9);
                }
                Log("逐文件替换完成，关键文件齐全");
                SafeDeleteDir(staging);
                Relaunch(targetFull, relaunch);
                Log("==== 更新成功 ====");
                return Done(0);
            }

            Log("改名 " + content + " -> " + targetFull);
            if (!TryMove(content, targetFull))
            {
                Log("新目录就位失败，回滚");
                if (TryMove(backup, targetFull))
                    Log("回滚成功，安装目录已恢复原状");
                else
                    Log("回滚也失败了！旧目录仍在 " + backup + "，需手动改回 " + targetFull);
                SafeDeleteDir(staging);
                RelaunchAfterFailure(targetFull, relaunch);
                return Fail(8);
            }

            // 换上去之后再确认一遍关键文件在位，不在就回滚
            foreach (string f in RequiredFiles)
            {
                if (!File.Exists(Path.Combine(targetFull, f)))
                {
                    Log("切换后缺少 " + f + "，回滚");
                    if (TryMove(targetFull, staging + "_bad") && TryMove(backup, targetFull))
                        Log("回滚成功");
                    else
                        Log("回滚失败！旧目录在 " + backup);
                    RelaunchAfterFailure(targetFull, relaunch);
                    return Fail(9);
                }
            }
            Log("切换完成，关键文件齐全");

            // 到这一步新版已确认可用，才允许删除旧目录
            SafeDeleteDir(backup);
            SafeDeleteDir(staging);

            // 安装包也一起删掉。它有 100MB 上下，装完就没用了，可之前一直留在
            // user://update 里没人管 —— 开发机上攒到过 12 个、1.2 GB，而用户根本
            // 不知道 AppData 里有这么个目录。
            //
            // 放在这里删：新版已经确认可用，回滚路径都走不到了，删了不会没退路。
            TryDeleteFile(zip);
            Log("已删除安装包 " + zip);

            Relaunch(targetFull, relaunch);
            Log("==== 更新成功 ====");
            return Done(0);
        }
        catch (Exception ex)
        {
            Log("未预期的异常: " + ex);
            return Fail(1);
        }
    }

    /// 等主程序退出。它还活着时安装目录里的文件被占用，改名会失败。
    private static void WaitForParent(int pid)
    {
        if (pid <= 0) return;
        try
        {
            Process p = Process.GetProcessById(pid);
            Log("等待主进程 " + pid + " 退出……");
            if (!p.WaitForExit(ParentWaitTimeoutMs))
                Log("等待超时（" + ParentWaitTimeoutMs + "ms），仍继续尝试");
            else
                Log("主进程已退出");
        }
        catch (ArgumentException)
        {
            Log("主进程已不存在，直接继续");
        }
        // 给系统一点时间释放文件句柄，否则紧接着改名容易撞上占用
        Thread.Sleep(800);
    }

    /// 等所有「可执行文件位于安装目录内」的进程退出。
    ///
    /// 只等主进程那一个 pid 是不够的：用户可能同时开着两个实例，或者上一次运行留下的
    /// 子进程还没退。这些进程都锁着安装目录里的文件，会让目录改名失败。
    private static void WaitForOccupants(string target)
    {
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < OccupantWaitMs)
        {
            var occupants = FindOccupants(target);
            if (occupants.Count == 0) return;

            if (sw.ElapsedMilliseconds < 1000)
                foreach (var o in occupants)
                    Log("安装目录内仍有进程在跑，等它退出: " + o);

            Thread.Sleep(500);
        }

        KillOccupants(target, "等待超时");
    }

    /// 强制结束占着安装目录的自家进程。
    ///
    /// 用户点了「更新」就意味着同意重启，所以杀掉自己的进程是正当的。这一步存在的
    /// 真正理由是：更新过程中桌宠会先消失几十秒，用户很容易以为它崩了而重新双击，
    /// 那个新实例会一直锁着安装目录，让改名从头到尾失败。实测的一次失败就是这样 ——
    /// 主进程按要求退了，7 秒后用户手动重开，之后 23 秒的重试全部落空。
    private static void KillOccupants(string target, string reason)
    {
        var list = FindOccupantProcesses(target);
        if (list.Count == 0) return;

        foreach (var p in list)
        {
            try
            {
                Log(reason + "，强制结束: " + p.ProcessName + " (pid " + p.Id + ")");
                p.Kill();
                p.WaitForExit(5000);
            }
            catch (Exception ex) { Log("  结束失败: " + ex.Message); }
        }
        // 给系统一点时间真正释放句柄
        Thread.Sleep(800);
    }


    // ------------------------------------------------------------ 逐文件替换

    /// 不动目录本身，只把里面的文件一个个换掉。
    ///
    /// 整目录改名（Directory.Move）要求目录自己和里面每一个文件都没有被任何进程打开，
    /// 一个都不行 —— 而实测有外部程序会短暂占住（杀软扫刚下载的安装包、资源管理器开着
    /// 那个文件夹），一次持续 30 秒以上，把重试窗口拉长只是碰运气。
    ///
    /// 逐文件替换的门槛低得多：只要那一个文件此刻可动就行。而且杀毒软件打开文件时
    /// 通常带 FILE_SHARE_DELETE（不然它一扫描就会弄坏正在运行的程序），所以扫描期间
    /// 改名往往仍然成功。真正的安装程序也是这么做的。
    ///
    /// 代价是失去了「一次改名、要么全成要么全不成」的原子性，所以这里自己记账：
    /// 每替换一个文件就把旧的那个改名留着，中途任何一步失败就按相反顺序全部还原。
    private static bool ReplaceFileByFile(string content, string target)
    {
        // 记录做过的动作，失败时按相反顺序还原
        var backedUp = new List<string[]>();  // {备份路径, 原路径}
        var placed = new List<string>();      // 已放上去的新文件

        try
        {
            foreach (string src in Directory.GetFiles(content, "*", SearchOption.AllDirectories))
            {
                string rel = src.Substring(content.Length).TrimStart(Path.DirectorySeparatorChar);
                string dst = Path.Combine(target, rel);
                Directory.CreateDirectory(Path.GetDirectoryName(dst));

                if (File.Exists(dst))
                {
                    string bak = dst + ".dororo_old";
                    TryDeleteFile(bak);
                    if (!TryMoveFile(dst, bak))
                    {
                        Log("  换不动 " + rel + "（一直被占用），放弃并还原");
                        RollbackFileByFile(backedUp, placed);
                        return false;
                    }
                    backedUp.Add(new string[] { bak, dst });
                }

                if (!TryMoveFile(src, dst))
                {
                    Log("  放不进 " + rel + "，放弃并还原");
                    RollbackFileByFile(backedUp, placed);
                    return false;
                }
                placed.Add(dst);
                Log("  已替换 " + rel);
            }
        }
        catch (Exception ex)
        {
            Log("  逐文件替换出错: " + ex.Message);
            RollbackFileByFile(backedUp, placed);
            return false;
        }

        // 全部换完才删备份。删不掉无所谓，那只是一份 .dororo_old 垃圾，
        // 下次更新会先清掉它。
        foreach (string[] pair in backedUp) TryDeleteFile(pair[0]);
        return true;
    }

    private static void RollbackFileByFile(List<string[]> backedUp, List<string> placed)
    {
        foreach (string f in placed) TryDeleteFile(f);
        for (int i = backedUp.Count - 1; i >= 0; i--)
        {
            string bak = backedUp[i][0], dst = backedUp[i][1];
            if (File.Exists(dst)) TryDeleteFile(dst);
            if (!TryMoveFile(bak, dst))
                Log("  还原失败！原文件留在 " + bak + "，需手动改回 " + dst);
        }
        Log("  已还原到更新前的状态");
    }

    /// 单个文件改名，短暂占用会自行消失，所以重试。
    private static bool TryMoveFile(string from, string to)
    {
        for (int i = 0; i < FileRetryCount; i++)
        {
            try { File.Move(from, to); return true; }
            catch { if (i == FileRetryCount - 1) return false; Thread.Sleep(FileRetryDelayMs); }
        }
        return false;
    }

    private static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    private static bool HasRequiredFiles(string dir)
    {
        foreach (string f in RequiredFiles)
            if (!File.Exists(Path.Combine(dir, f))) return false;
        return true;
    }

    // ------------------------------------------------------------ 重启

    /// 更新成功后把新版拉起来。
    private static void Relaunch(string targetFull, bool relaunch)
    {
        if (!relaunch) return;
        string exe = Path.Combine(targetFull, "dororo.exe");
        Log("重新启动 " + exe);
        try
        {
            Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = targetFull, UseShellExecute = false });
        }
        catch (Exception ex)
        {
            // 更新本身已成功，只是没能自动拉起，不算失败
            Log("重启失败（更新已完成，请手动启动）: " + ex.Message);
        }
    }

    /// 更新失败、已回滚之后，把原来那版桌宠重新拉起来。
    ///
    /// 这一步是用户体验上最要紧的补救：之前失败时桌宠就那么消失了，屏幕上什么都不剩，
    /// 用户完全不知道发生了什么、也不知道东西还在不在（实际上回滚过、一点没坏）。
    /// 现在至少她会自己回来，用户最多是「这次没更新上」，而不是「我的桌宠不见了」。
    private static void RelaunchAfterFailure(string targetFull, bool relaunch)
    {
        Console.WriteLine();
        Console.WriteLine("  ============================================");
        Console.WriteLine("     这次没更新成功，但你的桌宠一点没坏。");
        Console.WriteLine();
        Console.WriteLine("     原来那版会马上重新打开，照旧能用。");
        Console.WriteLine("     过一会儿再点一次「检查更新」通常就好了 ——");
        Console.WriteLine("     刚才是有别的程序（多半是杀毒软件在扫描");
        Console.WriteLine("     刚下载的安装包）临时占着文件。");
        Console.WriteLine("  ============================================");
        Console.WriteLine();
        if (!HasRequiredFiles(targetFull))
        {
            Log("安装目录里关键文件不齐，不敢自动启动，请手动检查 " + targetFull);
            return;
        }
        Relaunch(targetFull, relaunch);
    }

    /// 收尾：关日志并返回退出码。
    private static int Done(int code)
    {
        CloseLog();
        return code;
    }

    /// 开头打一条足够醒目的说明。
    ///
    /// 之前这个窗口只滚日志，用户看不出是什么东西、要多久、能不能动，于是在更新
    /// 途中把桌宠重新打开，直接导致更新失败。窗口标题和横幅就是为了防这一下。
    private static void Banner()
    {
        try { Console.Title = "Dororo 正在更新 —— 请勿重新打开桌宠"; } catch { }
        Console.WriteLine();
        Console.WriteLine("  ============================================");
        Console.WriteLine("     Dororo 正在更新，请稍候");
        Console.WriteLine();
        Console.WriteLine("     桌宠会先关闭，更新完成后自动重新打开。");
        Console.WriteLine("     这期间请不要手动打开桌宠，否则更新会失败。");
        Console.WriteLine("     整个过程通常十几秒，本窗口会自己关闭。");
        Console.WriteLine("  ============================================");
        Console.WriteLine();
    }

    /// 只可能是本程序自己的这几个进程占着安装目录。
    /// 刻意不去遍历系统里所有进程：Process.MainModule 对受保护进程既慢又可能阻塞，
    /// 放在每 500ms 的等待循环里会累积上万次调用，实测直接把助手卡死（第一版就是这样，
    /// 连日志都没来得及写）。杀毒软件、资源管理器这类占用我们也无权结束，
    /// 只在失败时单独报告即可。
    private static readonly string[] OwnProcessNames = { "dororo", "DoroInputBridge" };

    private static List<Process> FindOccupantProcesses(string target)
    {
        var found = new List<Process>();
        int self = Process.GetCurrentProcess().Id;
        foreach (string name in OwnProcessNames)
        {
            Process[] list;
            try { list = Process.GetProcessesByName(name); }
            catch { continue; }

            foreach (Process p in list)
            {
                try
                {
                    if (p.Id == self) continue;
                    string path = p.MainModule != null ? p.MainModule.FileName : null;
                    if (path != null && IsSameOrInside(Path.GetDirectoryName(path), target))
                        found.Add(p);
                }
                catch { /* 访问不到的进程（权限/已退出）跳过 */ }
            }
        }
        return found;
    }

    private static List<string> FindOccupants(string target)
    {
        var names = new List<string>();
        foreach (Process p in FindOccupantProcesses(target))
        {
            try { names.Add(p.ProcessName + " (pid " + p.Id + ")"); } catch { }
        }
        return names;
    }

    /// 改名失败后，尽量说清是谁挡着：先列进程，再逐个文件试独占打开，指出被占用的文件。
    /// 没有这些信息，用户只会看到「更新失败」，而我们也无从判断该怎么改。
    private static void ReportBlockers(string dir)
    {
        var procs = FindOccupants(dir);
        if (procs.Count == 0)
            Log("  没有进程的可执行文件位于安装目录内（可能是杀毒软件或资源管理器占用）");
        else
            foreach (var p in procs) Log("  仍在运行: " + p);

        try
        {
            foreach (string f in Directory.GetFiles(dir))
            {
                try
                {
                    using (File.Open(f, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) { }
                }
                catch (Exception ex)
                {
                    Log("  文件被占用: " + Path.GetFileName(f) + "  (" + ex.GetType().Name + ")");
                }
            }
        }
        catch (Exception ex) { Log("  列举文件失败: " + ex.Message); }
    }

    /// 解压结果里真正的内容根目录。安装包顶层通常还套着一层
    /// Dororo_vX.Y.Z_win\ 目录，所以先看根、再看每个一级子目录。
    private static string FindContentRoot(string staging)
    {
        if (HasRequired(staging)) return staging;
        foreach (string dir in Directory.GetDirectories(staging))
            if (HasRequired(dir)) return dir;
        return null;
    }

    private static bool HasRequired(string dir)
    {
        foreach (string f in RequiredFiles)
            if (!File.Exists(Path.Combine(dir, f))) return false;
        return true;
    }

    /// 目录改名。杀毒软件或残留句柄会让它短暂失败，所以重试几次再判定失败。
    private static bool TryMove(string from, string to, Action<int> onRetry = null)
    {
        for (int i = 0; i < RenameRetryCount; i++)
        {
            try
            {
                Directory.Move(from, to);
                return true;
            }
            catch (Exception ex)
            {
                if (i == RenameRetryCount - 1)
                {
                    Log("改名失败（第 " + (i + 1) + " 次，放弃）: " + ex.Message);
                    return false;
                }
                if (onRetry != null) onRetry(i);
                Thread.Sleep(RenameRetryDelayMs);
            }
        }
        return false;
    }

    private static void SafeDeleteDir(string dir)
    {
        if (!Directory.Exists(dir)) return;
        try { Directory.Delete(dir, true); }
        catch (Exception ex) { Log("删除 " + dir + " 失败（不影响更新结果）: " + ex.Message); }
    }

    private static bool IsSameOrInside(string path, string maybeParent)
    {
        string a = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
        string b = Path.GetFullPath(maybeParent).TrimEnd(Path.DirectorySeparatorChar);
        return a.Equals(b, StringComparison.OrdinalIgnoreCase)
            || a.StartsWith(b + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    // ------------------------------------------------------------------ 日志

    private static void OpenLog()
    {
        try
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Dororo");
            Directory.CreateDirectory(dir);
            _log = new StreamWriter(Path.Combine(dir, "update.log"), true) { AutoFlush = true };
        }
        catch { _log = null; }
    }

    private static void Log(string msg)
    {
        string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg;
        Console.WriteLine(line);
        if (_log != null) { try { _log.WriteLine(line); } catch { } }
    }

    private static void CloseLog()
    {
        if (_log != null) { try { _log.Dispose(); } catch { } _log = null; }
    }

    private static int Fail(int code)
    {
        Log("==== 更新未完成，退出码 " + code + " ====");
        CloseLog();
        return code;
    }
}
