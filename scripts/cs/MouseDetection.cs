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
		Viewport viewport = GetViewport();
		
		Image img = viewport.GetTexture().GetImage();
		Rect2 rect = viewport.GetVisibleRect();
		
		// Getting the mouse position in the viewport
		Vector2 mousePosition = viewport.GetMousePosition();
		int viewX = (int) ((int)mousePosition.X + rect.Position.X);

		int viewY = (int) ((int)mousePosition.Y + rect.Position.Y);

		// Getting the mouse position relative to the image (image will be the size of the window)
		int x = (int)(img.GetSize().X * viewX / rect.Size.X);
		int y = (int)(img.GetSize().Y * viewY / rect.Size.Y);

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