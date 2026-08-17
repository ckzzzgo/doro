using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Reflection;
using Godot;

public partial class AutoStarter : Node
{
	[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
	private static extern int SHGetKnownFolderPath(
		[MarshalAs(UnmanagedType.LPStruct)] Guid rfid, uint dwFlags, IntPtr hToken, out IntPtr ppszPath);

	private static readonly Guid FOLDERID_Startup = new Guid("{B97D20BB-F46A-4C97-BA10-5E3608430854}");

	public static void EnableAutoStart(string appName)
	{
		string startupPath = GetStartupFolderPath();
		if (string.IsNullOrEmpty(startupPath)) return;

		string shortcutPath = Path.Combine(startupPath, appName + ".lnk");

		string exePath;
		try
		{
			exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
		}
		catch (Exception ex)
		{
			// MainModule 在受限环境下会抛异常，原先这一句在 try 之外，会直接崩到调用方
			GD.PushWarning($"读取当前进程路径失败，无法创建开机自启快捷方式: {ex.Message}");
			return;
		}

		CreateShortcut(shortcutPath, exePath);
	}

	public static void DisableAutoStart(string appName)
	{
		string startupPath = GetStartupFolderPath();
		if (string.IsNullOrEmpty(startupPath)) return;

		string shortcutPath = Path.Combine(startupPath, appName + ".lnk");
		if (File.Exists(shortcutPath))
		{
			File.Delete(shortcutPath);
		}
	}

	public static bool IsAutoStartEnabled(string appName)
	{
		string startupPath = GetStartupFolderPath();
		if (string.IsNullOrEmpty(startupPath)) return false;

		string shortcutPath = Path.Combine(startupPath, appName + ".lnk");
		return File.Exists(shortcutPath);
	}

	// SHGetKnownFolderPath 返回的是 CoTaskMemAlloc 分配的缓冲区，调用方必须用
	// CoTaskMemFree 释放。原先直接 marshal 成 out string，CLR 只会拷出一份托管字符串、
	// 不释放原生内存，每次调用泄漏一小块。这里手动取字符串再释放。
	private static string GetStartupFolderPath()
	{
		IntPtr ptr = IntPtr.Zero;
		try
		{
			int hr = SHGetKnownFolderPath(FOLDERID_Startup, 0, IntPtr.Zero, out ptr);
			if (hr < 0 || ptr == IntPtr.Zero) return null;
			return Marshal.PtrToStringUni(ptr);
		}
		finally
		{
			if (ptr != IntPtr.Zero) Marshal.FreeCoTaskMem(ptr);
		}
	}

	private static void CreateShortcut(string shortcutPath, string targetPath)
	{
		// CoInitializeEx 的返回值必须判断：Godot 可能已把主线程初始化成 MTA，此时请求
		// STA 会返回 RPC_E_CHANGED_MODE（失败）。原先在 finally 里无条件 CoUninitialize，
		// 相当于替 Godot 减掉一次 COM 引用计数。只有自己初始化成功才配对释放。
		// 注意 S_FALSE(1) 表示"本线程已初始化过"，它也算成功，同样需要配对释放。
		int hr = CoInitializeEx(IntPtr.Zero, COINIT.COINIT_APARTMENTTHREADED);
		bool comInitialized = hr >= 0;
		object shell = null;

		try
		{
			Type shellLinkType = Type.GetTypeFromProgID("WScript.Shell");
			if (shellLinkType == null)
			{
				GD.PushWarning("WScript.Shell COM 类型不可用，无法创建开机自启快捷方式");
				return;
			}

			shell = Activator.CreateInstance(shellLinkType);
			if (shell == null)
			{
				GD.PushWarning("无法创建 WScript.Shell COM 实例");
				return;
			}

			// 通过 IDispatch 调用，避免直接做接口转换
			dynamic shellLink = shell.GetType().InvokeMember(
				"CreateShortcut",
				BindingFlags.InvokeMethod,
				null,
				shell,
				new object[] { shortcutPath });

			shellLink.TargetPath = targetPath;

			string workingDirectory = Path.GetDirectoryName(targetPath);
			if (!string.IsNullOrEmpty(workingDirectory))
			{
				shellLink.WorkingDirectory = workingDirectory;
			}

			shellLink.Save();
		}
		catch (Exception ex)
		{
			GD.PushWarning($"创建开机自启快捷方式失败: {ex.Message}");
		}
		finally
		{
			if (shell != null && Marshal.IsComObject(shell))
			{
				Marshal.FinalReleaseComObject(shell);
			}
			if (comInitialized)
			{
				CoUninitialize();
			}
		}
	}

	[DllImport("ole32.dll")]
	private static extern int CoInitializeEx(IntPtr pvReserved, COINIT dwCoInit);

	[DllImport("ole32.dll")]
	private static extern void CoUninitialize();

	private enum COINIT : uint
	{
		COINIT_APARTMENTTHREADED = 0x2,
		COINIT_MULTITHREADED = 0x0
	}
}
