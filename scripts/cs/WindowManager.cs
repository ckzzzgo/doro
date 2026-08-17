using Godot;
using System;
using System.Runtime.InteropServices;

public partial class WindowManager : Node
{
	// Windows API 导入（64 位安全：窗口样式用 GetWindowLongPtr/SetWindowLongPtr）
	[DllImport("user32.dll")]
	private static extern IntPtr GetActiveWindow();
	
	[DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
	private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
	
	[DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
	private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);
	
	[DllImport("user32.dll")]
	private static extern IntPtr GetForegroundWindow();

	[DllImport("user32.dll")]
	[return: MarshalAs(UnmanagedType.Bool)]
	private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
	
	[DllImport("user32.dll")]
	private static extern int GetSystemMetrics(int nIndex);

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
		_hWnd = GetActiveWindow();
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
		
		currentStyle = currentStyle | WS_EX_TOOLWINDOW;
		currentStyle = currentStyle & ~WS_EX_APPWINDOW;
		
		SetWindowLongPtr(_hWnd, GwlExStyle, new IntPtr(currentStyle));
	}

	public void HideTaskbarIcon()
	{
		if (_hWnd == IntPtr.Zero) return;
		
		long currentStyle = GetWindowLongPtr(_hWnd, GwlExStyle).ToInt64();
		
		currentStyle = currentStyle & ~WS_EX_APPWINDOW;
		currentStyle = currentStyle | WS_EX_TOOLWINDOW;
		
		SetWindowLongPtr(_hWnd, GwlExStyle, new IntPtr(currentStyle));
	}
	
	public bool IsOtherAppFullscreen()
	{
		IntPtr hWnd = GetForegroundWindow();
		RECT rect;
		if (hWnd != IntPtr.Zero && GetWindowRect(hWnd, out rect))
		{
			int windowWidth = rect.Right - rect.Left;
			int windowHeight = rect.Bottom - rect.Top;
			
			Godot.Vector2I screenSize = DisplayServer.ScreenGetSize();

			return windowWidth == screenSize.X && windowHeight == screenSize.Y;
		}
		else
		{
			return false;
		}
	}
}