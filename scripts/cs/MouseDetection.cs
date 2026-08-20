using Godot;

public partial class MouseDetection : Node
{
	
	// Autoloaded
	
	private WindowManager _api;
	public bool mouse_hovered = false;
	
	// 节流：GetImage() 每帧从 GPU 拷贝整张纹理到 CPU 开销不小，
	// 每 DETECT_FRAME_INTERVAL 个物理帧检测一次即可满足鼠标跟随需求。
	private const int DETECT_FRAME_INTERVAL = 2;
	private int _frame_counter = 0;

	// 粗筛挡掉了多少次、真正回读了多少次。留着是为了将来还能量 —— 这个优化的收益
	// 完全取决于「鼠标有多少时间不在窗口里」，那是个只能实测的比例。
	// 实测（窗口 400x400）：鼠标在窗口外 20 次全部跳过、0 次回读；
	// 在窗口内 20 次全部回读。
	public int SkippedReadbacks = 0;
	public int PerformedReadbacks = 0;
	
	[Signal]
	public delegate void MouseEnteredEventHandler();
	
	[Signal]
	public delegate void MouseExitedEventHandler();
	

	public override void _Ready()
	{
		_api = GetNode<WindowManager>("/root/WindowManager");
		
		// initializing as click-through
		_api.SetClickThrough(true);
	}
	
	// it is better to detect the pixels only when rendered, so PhysicsProcess is recommended
	public override void _PhysicsProcess(double delta)
	{
		_frame_counter++;
		if (_frame_counter >= DETECT_FRAME_INTERVAL)
		{
			_frame_counter = 0;
			DetectPassthrough();
		}
	}

	
	// Detection of what color is the pixel under the mouse cursor, based on the viewport texture
	// This can become expensive if done every frame and in more complex scenes.
	// We will use this to determine whether the window should be clickable or not
	// You can choose any other method of detection!
	private void DetectPassthrough()
	{
		// 用系统全局鼠标坐标换算窗口内偏移更可靠：点击透明穿透窗口下，
		// viewport.GetMousePosition() 可能不随鼠标更新（窗口不接收鼠标消息）。
		// 用 DisplayServer 全局坐标 + 窗口屏幕位置计算，穿透窗口也能正确检测。
		Vector2I windowPos = DisplayServer.WindowGetPosition();
		Vector2I screenMouse = DisplayServer.MouseGetPosition();
		Vector2 mousePosition = new Vector2(
			screenMouse.X - windowPos.X,
			screenMouse.Y - windowPos.Y);

		// mousePosition 已经是「窗口像素」，要换算到「纹理像素」。
		//
		// 原实现除的是 viewport.GetVisibleRect()，那是**逻辑**视口尺寸 —— 本项目用
		// canvas_items 拉伸，它恒为 640x640，与窗口缩放无关；而纹理尺寸等于窗口实际
		// 尺寸。于是 img/rect 正好等于缩放比例，等价于把已经是窗口像素的鼠标坐标
		// 又乘了一次缩放，缩得越小偏得越狠：
		//   缩放 0.6 时鼠标在窗口正中(192,192) 采样点跑到 (115,115)
		//   缩放 0.1 时鼠标在窗口正中(32,32)   采样点跑到 (3,3)
		// 缩到最小时整个 64x64 窗口的采样点都被压进左上角 0~6 像素，那里永远透明，
		// 于是永远检测不到悬停：不能拖、不能摸、点击穿透常开。而 window_scale 存在
		// 配置里，重启后依旧如此。
		//
		// 正确的换算是「窗口尺寸 -> 纹理尺寸」。二者相等时即恒等，写成比例也能扛住
		// 将来帧缓冲与窗口尺寸不一致的情况（例如 HiDPI）。
		Vector2I windowSize = DisplayServer.WindowGetSize();
		if (windowSize.X <= 0 || windowSize.Y <= 0) return;

		// 粗筛：鼠标不在窗口里就不必回读画面。
		//
		// GetImage() 是把整张画面从显存拷回内存，代价随窗口**面积**增长，实测
		// 640x640 单次 1.22ms、1024x1024 单次 2.67ms；而它每秒跑 30 次（物理帧每两帧
		// 一次），也就是放大到 1.6 倍时每秒有 80ms 花在这上面 —— 只为了看鼠标底下
		// 那一个像素透不透明。
		//
		// 而桌宠的窗口在屏幕上只占一小块（640x640 在 1920x1080 上约两成面积），
		// 绝大多数时候鼠标根本不在窗口范围内。这一层判断只用到窗口坐标和窗口尺寸，
		// 不需要任何画面数据，所以能在回读之前就把大部分帧挡掉。
		bool insideWindow =
			mousePosition.X >= 0 && mousePosition.X < windowSize.X &&
			mousePosition.Y >= 0 && mousePosition.Y < windowSize.Y;

		if (!insideWindow)
		{
			// 顺带修一个老问题：原先越界时函数什么都不做，直接跳过下面的判定，
			// 于是 mouse_hovered 和点击穿透都停在上一次的值上 —— 鼠标从她身上快速
			// 划出窗口时，会留下"仍在悬停"的状态，点击穿透一直关着。
			// 出了窗口就是没在悬停，如实收尾。
			SkippedReadbacks++;
			SetClickability(false);
			if (mouse_hovered)
			{
				EmitSignal(SignalName.MouseExited);
				mouse_hovered = false;
			}
			return;
		}

		PerformedReadbacks++;
		Image img = GetViewport().GetTexture().GetImage();

		int x = (int)(mousePosition.X * img.GetSize().X / windowSize.X);
		int y = (int)(mousePosition.Y * img.GetSize().Y / windowSize.Y);

		// Getting the pixel at the mouse position coordinates
		if (x < img.GetSize().X && x>=0 && y < img.GetSize().Y && y>=0)
		{
			Color pixel = img.GetPixel(x, y);
			SetClickability(pixel.A > 0.5f);
			
			if (pixel.A > 0.5f){
				if (!mouse_hovered) EmitSignal(SignalName.MouseEntered);
				mouse_hovered = true;
			}
			else{
				if(mouse_hovered) EmitSignal(SignalName.MouseExited);
				mouse_hovered = false;
			}
		}
		else{
			if(mouse_hovered) EmitSignal(SignalName.MouseExited);
			mouse_hovered = false;
		}

		// Very important to dispose the rendered image or will bloat memory !!!!!
		img.Dispose();
	}
	
	// instead of calling the API every frame, we check if the state is changed and then call it if necessary
	private bool _clickthrough = true;
	private void SetClickability(bool clickable)
	{
		if (clickable != _clickthrough)
		{
			_clickthrough = clickable;
			// clickthrough means NOT clickable
			_api.SetClickThrough(!clickable);
		}
	}
}