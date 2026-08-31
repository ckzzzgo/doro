using System;
using System.Runtime.InteropServices;
using System.Text;
using Godot;

/// <summary>
/// 用 Windows DPAPI 加解密配置里的凭据（目前只有 chat/api_key）。
///
/// 为什么直接 P/Invoke crypt32 而不用 System.Security.Cryptography.ProtectedData：
/// .NET 8 上那个类要单独装 NuGet 包，而本项目的 csproj 至今零依赖、打包走纯命令行
/// headless 导出。加一个包就是给构建链多一个失败点（还得保证那个 DLL 跟着进包）。
/// 项目本来就重度 P/Invoke（WindowManager 整个都是），直接调底层反而更一致、更稳。
///
/// 它挡得住什么，挡不住什么 —— 别搞混：
///   挡得住  别人拿到 config.ini 这个文件本身：借走的笔记本、截图、同步到网盘的
///           备份、用户把日志或配置发给别人排查。这是最常见的泄露路径。
///   挡不住  以同一个 Windows 账号运行的程序。它自己也能调 CryptUnprotectData，
///           拿到的东西跟我们一样。DPAPI 的密钥就是绑在账号上的，这是设计如此。
/// 所以对外别说成「密钥已加密保护」，只能说「不再明文存放」。
/// </summary>
public partial class SecretStore : Node
{
	/// 存进配置文件时加的前缀。用来区分「已加密」和「老版本留下的明文」，
	/// 迁移逻辑靠它判断（见 config_manager.gd）。
	public const string Prefix = "dpapi:";

	/// 附加熵。DPAPI 允许在账号密钥之外再掺一段自定的数据，解密时必须给出同一段。
	/// 挡不住反编译（这串就在程序里），但能让「同机器上另一个程序顺手解开」这件事
	/// 不再是一行代码的事 —— 白给的一点门槛，不要白不要。
	private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Dororo/config/v1");

	/// 绝不弹 UI。这是个后台桌宠，DPAPI 真要弹个提示框出来会很莫名其妙。
	private const uint CRYPTPROTECT_UI_FORBIDDEN = 0x1;

	[StructLayout(LayoutKind.Sequential)]
	private struct DATA_BLOB
	{
		public int cbData;
		public IntPtr pbData;
	}

	[DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
	private static extern bool CryptProtectData(
		ref DATA_BLOB pDataIn, string szDataDescr, ref DATA_BLOB pOptionalEntropy,
		IntPtr pvReserved, IntPtr pPromptStruct, uint dwFlags, out DATA_BLOB pDataOut);

	[DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
	private static extern bool CryptUnprotectData(
		ref DATA_BLOB pDataIn, IntPtr ppszDataDescr, ref DATA_BLOB pOptionalEntropy,
		IntPtr pvReserved, IntPtr pPromptStruct, uint dwFlags, out DATA_BLOB pDataOut);

	[DllImport("kernel32.dll")]
	private static extern IntPtr LocalFree(IntPtr hMem);

	/// 写成实例方法而不是 static：GDScript 通过 Object.call 调过来，
	/// Godot 的 C# 绑定只登记公开的**实例**方法，static 的调不到。

	/// 明文 -> "dpapi:" + base64。失败返回空串，调用方据此退回明文存储。
	public string Protect(string plain)
	{
		if (string.IsNullOrEmpty(plain)) return "";
		byte[] cipher = Transform(Encoding.UTF8.GetBytes(plain), true);
		if (cipher == null) return "";
		return Prefix + Convert.ToBase64String(cipher);
	}

	/// "dpapi:..." -> 明文。解不开返回空串 —— 配置被拷到别的机器或换了 Windows
	/// 账号时就是这个下场，属于预期内，调用方要提示用户重填，不能崩。
	public string Unprotect(string stored)
	{
		if (string.IsNullOrEmpty(stored) || !stored.StartsWith(Prefix)) return "";
		byte[] raw;
		try
		{
			raw = Convert.FromBase64String(stored.Substring(Prefix.Length));
		}
		catch (FormatException)
		{
			GD.PushWarning("SecretStore: 密文不是合法的 base64，配置可能被手工改过");
			return "";
		}
		byte[] plain = Transform(raw, false);
		return plain == null ? "" : Encoding.UTF8.GetString(plain);
	}

	/// 这串值是不是已经加密过的。
	public bool IsProtected(string stored)
	{
		return !string.IsNullOrEmpty(stored) && stored.StartsWith(Prefix);
	}

	/// 当前环境能不能用 DPAPI。加密一个探针串试试 —— 非 Windows、或 crypt32 缺失时
	/// 直接返回 false，调用方退回明文（功能可用优先于加密）。
	public bool IsAvailable()
	{
		try
		{
			return Protect("probe").Length > Prefix.Length;
		}
		catch (Exception)
		{
			return false;
		}
	}

	private static byte[] Transform(byte[] input, bool encrypt)
	{
		var inBlob = new DATA_BLOB();
		var entBlob = new DATA_BLOB();
		var outBlob = new DATA_BLOB();
		try
		{
			inBlob.pbData = Marshal.AllocHGlobal(input.Length);
			inBlob.cbData = input.Length;
			Marshal.Copy(input, 0, inBlob.pbData, input.Length);

			entBlob.pbData = Marshal.AllocHGlobal(Entropy.Length);
			entBlob.cbData = Entropy.Length;
			Marshal.Copy(Entropy, 0, entBlob.pbData, Entropy.Length);

			bool ok = encrypt
				? CryptProtectData(ref inBlob, null, ref entBlob, IntPtr.Zero, IntPtr.Zero,
					CRYPTPROTECT_UI_FORBIDDEN, out outBlob)
				: CryptUnprotectData(ref inBlob, IntPtr.Zero, ref entBlob, IntPtr.Zero, IntPtr.Zero,
					CRYPTPROTECT_UI_FORBIDDEN, out outBlob);
			if (!ok)
			{
				// 解密失败是预期内的（换机器/换账号），不当错误刷屏；加密失败才值得警告。
				if (encrypt)
				{
					GD.PushWarning($"SecretStore: 加密失败（Win32 错误 {Marshal.GetLastWin32Error()}），将退回明文存储");
				}
				return null;
			}

			var result = new byte[outBlob.cbData];
			Marshal.Copy(outBlob.pbData, result, 0, outBlob.cbData);
			return result;
		}
		catch (DllNotFoundException)
		{
			return null;   // 非 Windows：调用方退回明文
		}
		catch (Exception ex)
		{
			GD.PushWarning($"SecretStore: {(encrypt ? "加密" : "解密")}时出错：{ex.Message}");
			return null;
		}
		finally
		{
			// 三块内存分属两个分配器：入参和熵是我们 AllocHGlobal 的，
			// 出参是 crypt32 内部分配的，必须用 LocalFree 还回去，混用会泄漏。
			if (inBlob.pbData != IntPtr.Zero) Marshal.FreeHGlobal(inBlob.pbData);
			if (entBlob.pbData != IntPtr.Zero) Marshal.FreeHGlobal(entBlob.pbData);
			if (outBlob.pbData != IntPtr.Zero) LocalFree(outBlob.pbData);
		}
	}
}
