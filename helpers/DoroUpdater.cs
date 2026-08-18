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
    private const int RenameRetryCount = 40;
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
            Log("改名 " + targetFull + " -> " + backup);
            if (!TryMove(targetFull, backup))
            {
                Log("旧目录改名失败，未做任何改动。下面列出还占着安装目录的东西：");
                ReportBlockers(targetFull);
                SafeDeleteDir(staging);
                return Fail(7);
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
                    return Fail(9);
                }
            }
            Log("切换完成，关键文件齐全");

            // 到这一步新版已确认可用，才允许删除旧目录
            SafeDeleteDir(backup);
            SafeDeleteDir(staging);

            if (relaunch)
            {
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

            Log("==== 更新成功 ====");
            CloseLog();
            return 0;
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

        // 等不到就强制结束 —— 这些都是本程序自己的进程，用户点了更新即表示同意重启
        foreach (var p in FindOccupantProcesses(target))
        {
            try
            {
                Log("等待超时，强制结束: " + p.ProcessName + " (pid " + p.Id + ")");
                p.Kill();
                p.WaitForExit(5000);
            }
            catch (Exception ex) { Log("  结束失败: " + ex.Message); }
        }
        Thread.Sleep(800);
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
    private static bool TryMove(string from, string to)
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
