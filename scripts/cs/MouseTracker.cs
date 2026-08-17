using Godot;
using System.Runtime.InteropServices;

public partial class MouseTracker : Node
{
	// 定义 POINT 结构体（用于接收系统坐标）
	[StructLayout(LayoutKind.Sequential)]
	public struct POINT
	{
		public int X;
		public int Y;
	}

	// 导入 Windows API 函数
	[DllImport("user32.dll")]
	[return: MarshalAs(UnmanagedType.Bool)]
	public static extern bool GetCursorPos(out POINT lpPoint);

	/// 系统全局鼠标坐标。点击穿透窗口收不到鼠标消息，Godot 自身的鼠标位置可能不更新，
	/// 所以窗口拖拽等逻辑一律用这里的 Win32 坐标算。
	public Vector2I GetMousePosition()
	{
		if (GetCursorPos(out POINT point))
		{
			return new Vector2I(point.X, point.Y);
		}
		else
		{
			return Vector2I.Zero;
		}
	}
}
