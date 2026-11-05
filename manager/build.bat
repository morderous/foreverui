@echo off
rem Builds ForeverUIManager.exe with the C# compiler that comes with Windows
rem (.NET Framework 4.8). No download, no package, nothing else to install.
rem Give a path to build somewhere else: build.bat C:\somewhere\ForeverUIManager.exe
cd /d "%~dp0"
set OUT=ForeverUIManager.exe
if not "%~1"=="" set OUT=%~1
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /optimize+ ^
  /out:"%OUT%" ^
  /reference:System.Windows.Forms.dll /reference:System.Drawing.dll ^
  /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll ^
  /reference:System.Web.Extensions.dll /reference:System.Numerics.dll ^
  ForeverUIManager.cs
