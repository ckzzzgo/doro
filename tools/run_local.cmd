@echo off
setlocal

rem  本地试跑 Doro。逻辑在同目录的 run_local.ps1 里，这里只负责把它拉起来。
rem
rem  默认跑【打好的包】，也就是用户下载到的那个东西 —— 跑源码和跑包不是同一回事，
rem  1.4.1 就是栽在这上面（源码走 Vulkan 正常，包走 OpenGL 全黑）。
rem  如果你的代码比包新，脚本会拦住问一句，不会默默让你测一个旧包。
rem
rem  本文件必须是 GBK 编码 + CRLF 换行：cmd.exe 按系统代码页读脚本，
rem  存成 UTF-8 会让中文注释从中间截断，换成 LF 会让 if() 块解析错乱。

set "PS=%~dp0run_local.ps1"

if not exist "%PS%" (
  echo [X] 找不到 run_local.ps1:
  echo     %PS%
  pause
  exit /b 1
)

where pwsh >nul 2>&1
if errorlevel 1 (
  echo [X] 找不到 pwsh（PowerShell 7）。
  echo     装一个，或者直接用 Godot 打开项目跑。
  pause
  exit /b 1
)

pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS%" %*

echo.
pause
