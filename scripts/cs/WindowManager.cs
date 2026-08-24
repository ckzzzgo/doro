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
	private static extern bool SetForegroundWindow(IntPtr hWnd);

	[DllImport("user32.dll")]
	[return: MarshalAs(UnmanagedType.Bool)]
	private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

	[DllImport("user32.dll")]
	[return: MarshalAs(UnmanagedType.Bool)]
	private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
		int X, int Y, int cx, int cy, uint uFlags);

	private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
	private static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
	private const uint SWP_NOSIZE = 0x0001;
	private const uint SWP_NOMOVE = 0x0002;
	private const uint SWP_NOACTIVATE = 0x0010;

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

	// 期望的置顶状态。必须由本类持有：SetClickThrough 每次重写扩展样式都会把窗口
	// 挤出置顶层，写完得立刻按这个意图重新施加一次。
	private bool _topmost = false;

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

	/// 给窗口补上 TOOLWINDOW，让它不出现在任务栏。
	///
	/// 注意这只管住「以后」：按钮是窗口创建那一刻登记的，登记之后再改扩展样式
	/// 赶不走它。真正让按钮压根不出现的是 project.godot 里的 no_focus
	/// （窗口创建时就带上 WS_EX_NOACTIVATE）。这里是给子窗口用的 —— 它们由
	/// Godot 懒创建，创建时机在项目设置管不到的地方，只能创建后补。
	///
	/// 想「把已经登记的按钮摘掉、或把已经打上的橙色高亮清掉」的手段全试过，全都
	/// 无效，别再往这里加（下面说的无效都只针对这一件事）：
	///   ITaskbarList.DeleteTab     本机 CLSID 未注册（REGDB_E_CLASSNOTREG）
	///   ShowWindow hide/show       按钮不动
	///   设 owner (GWLP_HWNDPARENT) 按钮不动
	///   FlashWindowEx(FLASHW_STOP) 高亮不消
	///   SetForegroundWindow        高亮不消
	///
	/// 最后一条不代表 SetForegroundWindow 没用 —— 它清不掉高亮，但能让窗口拿到
	/// 键盘焦点，FocusMainWindow 就靠它让输入框能打字。两件事别混。
	private void SetToolWindowStyle(IntPtr h)
	{
		if (h == IntPtr.Zero) return;
		long style = GetWindowLongPtr(h, GwlExStyle).ToInt64();
		SetWindowLongPtr(h, GwlExStyle, new IntPtr((style | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW));
	}

	/// 主动把主窗口拿到前台，让输入框能接收键盘。
	///
	/// 为什么需要：主窗口开了 display/window/size/no_focus（WS_EX_NOACTIVATE）——
	/// 不开的话任务栏上会冒出一个一直橙色高亮的按钮，开机自启动时必现且事后清不掉。
	/// 代价是窗口不会因为用户点击而自动获得键盘焦点，聊天输入框打不了字。
	///
	/// 为什么不用 Godot 的 DisplayServer.window_move_to_foreground()：实测对这个窗口
	/// 不起作用，输入框照样打不了字。而 Win32 的 SetForegroundWindow 对同一个窗口是
	/// 有效的（实测返回 true，前台窗口确实变成了她）—— NOACTIVATE 只挡「点击自动
	/// 激活」，不挡程序主动激活，是那个 API 的实现不给力。
	///
	/// 这不会让她出现在任务栏：任务栏可见性由扩展样式决定，跟当前谁是前台窗口无关。
	public void FocusMainWindow()
	{
		if (_hWnd == IntPtr.Zero) return;
		if (!SetForegroundWindow(_hWnd))
		{
			GD.PushWarning("SetForegroundWindow 失败，输入框可能仍然打不了字");
		}
	}

	private void InitializeWindowStyle()
	{
		long currentStyle = GetWindowLongPtr(_hWnd, GwlExStyle).ToInt64();

		// 顺手在这里就把 TOOLWINDOW 设上，不留给第一次 SetClickThrough。
		//
		// 别指望它能解决任务栏按钮：按钮是窗口创建那一刻登记的，而本方法在那之后
		// 才跑，改样式赶不走已经登记的按钮。真正让按钮压根不出现的是 project.godot
		// 里的 no_focus（创建时就带上 WS_EX_NOACTIVATE）。
		//
		// 那为什么还要在这里设？因为 TOOLWINDOW 还管另一件事 —— 窗口不出现在
		// Alt+Tab 列表里。原来它只在 SetClickThrough 里设，得等鼠标第一次移进或
		// 移出桌宠；在那之前按 Alt+Tab 会看到她。提前设掉这段空窗期。
		long newStyle = (currentStyle | WsExLayered | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
		SetWindowLongPtr(_hWnd, GwlExStyle, new IntPtr(newStyle));
	}

	/// 让一个子窗口不在任务栏留按钮。
	///
	/// 设置窗、聊天记录窗、对话气泡都是独立的 OS 窗口，而 Windows 会给每个显示出来的
	/// 顶层窗口登记一个任务栏按钮。桌宠不该在任务栏露面，可本类的初始化只覆盖主窗口，
	/// 这三个一直没人管：一打开设置，任务栏上就多一个按钮。
	///
	/// 别和「开机后那个一直橙色高亮的按钮」搞混 —— 那个是【主窗口】的，由
	/// project.godot 里的 no_focus 解决。排查时我一度以为是这三个子窗口造成的，
	/// 后来枚举窗口证明不是（主窗口 TOOLWINDOW 明明设着，按钮却还在）。
	/// 这里修的是另一件事：子窗口显示时各自多一个普通按钮，跟橙色无关。
	///
	/// 为什么不用 Godot 的 Window.transient：试过，不管用。Win32 层面的 owner 压根
	/// 没被设上（实测 GetWindow(GW_OWNER) 仍然返回 0），按钮照旧出现。
	///
	/// 为什么要等窗口显示出来才动手：Godot 是懒创建 OS 窗口的，visible=false 时那个
	/// 窗口还不存在，拿不到句柄（实测枚举只能看到已经显示的那些）。所以没法「先设好
	/// 样式再显示」，只能在它显示的那一刻补救。
	public void KeepOutOfTaskbar(Window w)
	{
		if (w == null) return;

		bool handled = false;

		void Fix()
		{
			// 只做一次。TOOLWINDOW 一旦设上就是永久的，之后再显示不会重新登记。
			if (handled || !w.Visible) return;
			handled = true;

			int id = (int)w.GetWindowId();
			IntPtr h = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle, id);
			if (h == IntPtr.Zero)
			{
				GD.PushWarning($"KeepOutOfTaskbar: 取不到 {w.Name} 的窗口句柄（id={id}），它会留在任务栏");
				return;
			}

			SetToolWindowStyle(h);
		}

		w.VisibilityChanged += Fix;

		// 还得立刻自查一次：窗口有可能在我们连上信号之前就已经是可见的
		// （场景文件里直接设了 visible=true 的情况），那 VisibilityChanged
		// 永远不会再响，光挂信号等于没修。
		Fix();
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

		// 关键：上面这次 SetWindowLongPtr 会把窗口挤出置顶层。本方法在鼠标每次
		// 移进/移出桌宠时都会被调用，所以不在这里补一刀，置顶就会在一两帧内消失。
		// 这正是「置顶按钮点了没反应」的真正原因 —— 开与关在系统看来都是不置顶。
		ApplyTopmost();
	}

	/// 设置置顶。置顶必须走 SetWindowPos —— 往扩展样式里直接写 WS_EX_TOPMOST
	/// 是不算数的（Win32 明确要求用 SetWindowPos 改变置顶层）。
	public void SetTopmost(bool topmost)
	{
		_topmost = topmost;
		ApplyTopmost();
	}

	public bool GetTopmost()
	{
		return _topmost;
	}

	private void ApplyTopmost()
	{
		if (_hWnd == IntPtr.Zero) return;

		// SWP_NOACTIVATE：桌宠不该因为重设置顶而抢走焦点
		SetWindowPos(
			_hWnd,
			_topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
			0, 0, 0, 0,
			SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
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
