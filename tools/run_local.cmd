@echo off
setlocal

rem  本地试跑 Doro：直接用 Godot 跑项目源码，不打包。
rem
rem  完整导出一次要 10 分钟，改一行 GDScript 想看效果不该等那么久；这条路十几秒出画面。
rem
rem  和正式安装包的区别只有两条：
rem    1. debug 构建，控制台会多打一些 [DORO] 调试日志，release 版是静音的
rem    2. 走项目源码而不是 pck，改完存盘直接再点一次就是新的
rem  配置文件是同一个，API Key、缩放、位置这些和正式版共用，不用重填。
rem
rem  本文件必须是 GBK 编码 + CRLF 换行：cmd.exe 按系统代码页读脚本，
rem  存 UTF-8 会把中文注释从中间截断，换成 LF 会让 if() 块解析出错。两个坑都踩过。

set "REPO=%~dp0.."
set "GODOT=%USERPROFILE%\Desktop\Godot_v4.4.1_mono\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64_console.exe"
set "DOTNET=C:\Program Files\dotnet"

if not exist "%GODOT%" (
  echo [X] 找不到 Godot:
  echo     %GODOT%
  pause
  exit /b 1
)

if not exist "%REPO%\project.godot" (
  echo [X] 找不到 project.godot，这里不像是项目目录:
  echo     %REPO%
  pause
  exit /b 1
)

set "PATH=%DOTNET%;%PATH%"

echo [1/2] 编译 C# ...
cd /d "%REPO%"
dotnet build -v quiet -nologo
if errorlevel 1 (
  echo.
  echo [X] C# 编译失败，看上面的错误
  pause
  exit /b 1
)

echo [2/2] 启动 Doro ...
echo.
echo     关掉这个黑窗口就等于退出 Doro
echo.
"%GODOT%" --path .

echo.
echo Doro 已退出。
pause
