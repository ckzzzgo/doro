using System;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class DoroInputBridge
{
    private const int DefaultPort = 47329;
    private const int PollIntervalMs = 8;
    private const int ParentCheckIntervalMs = 500;

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out Point point);

    private static bool IsPressed(int virtualKey)
    {
        return (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
    }

    private static bool IsMouseButton(int virtualKey)
    {
        return virtualKey >= 0x01 && virtualKey <= 0x06;
    }

    private static void Send(UdpClient client, IPEndPoint target, string message)
    {
        byte[] payload = Encoding.ASCII.GetBytes(message);
        client.Send(payload, payload.Length, target);
    }

    private static bool ParentIsAlive(int parentPid)
    {
        if (parentPid <= 0)
        {
            return true;
        }

        try
        {
            Process process = Process.GetProcessById(parentPid);
            return !process.HasExited;
        }
        catch
        {
            return false;
        }
    }

    private static int ReadIntegerArgument(string[] args, string name, int fallback)
    {
        for (int index = 0; index + 1 < args.Length; index++)
        {
            if (String.Equals(args[index], name, StringComparison.OrdinalIgnoreCase))
            {
                int value;
                if (Int32.TryParse(args[index + 1], out value))
                {
                    return value;
                }
            }
        }

        return fallback;
    }

    private static void Main(string[] args)
    {
        int port = ReadIntegerArgument(args, "--port", DefaultPort);
        int parentPid = ReadIntegerArgument(args, "--parent", 0);
        IPEndPoint target = new IPEndPoint(IPAddress.Loopback, port);
        bool[] keyStates = new bool[256];

        for (int virtualKey = 1; virtualKey < keyStates.Length; virtualKey++)
        {
            keyStates[virtualKey] = IsPressed(virtualKey);
        }

        Point lastPoint;
        if (!GetCursorPos(out lastPoint))
        {
            lastPoint = new Point();
        }

        long lastParentCheck = Environment.TickCount;

        using (UdpClient client = new UdpClient())
        {
            while (true)
            {
                long now = Environment.TickCount;
                if (unchecked(now - lastParentCheck) >= ParentCheckIntervalMs)
                {
                    if (!ParentIsAlive(parentPid))
                    {
                        return;
                    }

                    lastParentCheck = now;
                }

                Point point;
                if (GetCursorPos(out point) && (point.X != lastPoint.X || point.Y != lastPoint.Y))
                {
                    Send(client, target, "MM|" + point.X + "|" + point.Y);
                    lastPoint = point;
                }

                for (int virtualKey = 1; virtualKey < keyStates.Length; virtualKey++)
                {
                    bool pressed = IsPressed(virtualKey);
                    if (pressed == keyStates[virtualKey])
                    {
                        continue;
                    }

                    keyStates[virtualKey] = pressed;
                    if (IsMouseButton(virtualKey))
                    {
                        Send(client, target, (pressed ? "MD|" : "MU|") + virtualKey);
                    }
                    else
                    {
                        Send(client, target, (pressed ? "KD|" : "KU|") + virtualKey);
                    }
                }

                Thread.Sleep(PollIntervalMs);
            }
        }
    }
}
