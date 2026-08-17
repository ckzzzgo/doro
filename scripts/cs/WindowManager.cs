using Godot;
using System;
using System.Runtime.InteropServices;

public partial class WindowManager : Node
{
	// Windows API 导入（64 位安全：窗口样式用 GetWindowLongPtr/SetWindowLongPtr）
	[DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
	private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

	[DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
	private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

	[DllImport("user32.dll")]
	private static extern IntPtr GetForegroundWindow();

	[DllImport("user32.dll")]
	[return: MarshalAs(UnmanagedType.Bool)]
	private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

	private struct RECT
	{
		public int Left;
		public int Top;
		public int Right;
		public int Bottom;
	}

	// 常量定义
	private const int GwlExStyle = -20;

	// 点击穿透相关样式
	private const long WsExLayered = 0x00080000;
	private const long WsExTransparent = 0x00000020;

	// 任务栏图标相关样式
	private const long WS_EX_APPWINDOW = 0x00040000;
	private const long WS_EX_TOOLWINDOW = 0x00000080;

	private IntPtr _hWnd;

	public override void _Ready()
	{
		// 不能用 GetActiveWindow()：它只在「调用线程当前有活动窗口」时才返回句柄，
		// 进程启动时窗口尚未获得焦点（开机自启、从后台拉起等）就会返回 NULL，
		// 之后 SetClickThrough 全被 _hWnd == Zero 的守卫挡掉，点击穿透会全程静默失效。
		// 直接向 Godot 要真实窗口句柄，与焦点无关。
		_hWnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
		if (_hWnd == IntPtr.Zero)
		{
			GD.PushError("WindowManager: 取窗口句柄失败，点击穿透将无法工作");
			return;
		}
		InitializeWindowStyle();
	}

	private void InitializeWindowStyle()
	{
		long currentStyle = GetWindowLongPtr(_hWnd, GwlExStyle).ToInt64();
		long newStyle = currentStyle | WsExLayered;
		SetWindowLongPtr(_hWnd, GwlExStyle, new IntPtr(newStyle));
	}

	public void SetClickThrough(bool clickthrough)
	{
		if (_hWnd == IntPtr.Zero) return;

		long currentStyle = GetWindowLongPtr(_hWnd, GwlExStyle).ToInt64();

		currentStyle = currentStyle & ~(WsExLayered | WsExTransparent);

		if (clickthrough)
		{
			currentStyle = currentStyle | (WsExLayered | WsExTransparent);
		}
		else
		{
			currentStyle = currentStyle | WsExLayered;
		}

		// 下面两行是桌宠"不出现在任务栏"的唯一实现路径，看着像冗余但别删：
		// 每次穿透状态切换时重新施加，也顺带兜住 Godot 内部重设扩展样式的情况。
		currentStyle = currentStyle | WS_EX_TOOLWINDOW;
		currentStyle = currentStyle & ~WS_EX_APPWINDOW;

		SetWindowLongPtr(_hWnd, GwlExStyle, new IntPtr(currentStyle));
	}

	/// 前台窗口是否正好铺满它所在的那块屏幕。
	///
	/// 原实现用 DisplayServer.ScreenGetSize() 取的是桌宠自己所在屏的尺寸，而前台窗口
	/// 可能在另一块屏上 —— 分辨率不同的多屏环境会误判（该躲的时候不躲，或反之）。
	/// 这里逐屏比对位置与尺寸；前台窗口就是桌宠自己时直接排除。
	public bool IsOtherAppFullscreen()
	{
		IntPtr hWnd = GetForegroundWindow();
		if (hWnd == IntPtr.Zero || hWnd == _hWnd) return false;
		if (!GetWindowRect(hWnd, out RECT rect)) return false;

		int windowWidth = rect.Right - rect.Left;
		int windowHeight = rect.Bottom - rect.Top;

		int screenCount = DisplayServer.GetScreenCount();
		for (int i = 0; i < screenCount; i++)
		{
			Godot.Vector2I pos = DisplayServer.ScreenGetPosition(i);
			Godot.Vector2I size = DisplayServer.ScreenGetSize(i);
			if (rect.Left == pos.X && rect.Top == pos.Y
				&& windowWidth == size.X && windowHeight == size.Y)
			{
				return true;
			}
		}

		return false;
	}
}
