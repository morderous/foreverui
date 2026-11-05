#!/bin/sh
# Builds the app and its checks into tests/out (never over a ForeverUIManager.exe
# in use) and runs the checks. Arguments go to Tests.exe: live, or zip <file>.
set -e
# Git Bash would turn csc's /options into paths.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
here="$(cd "$(dirname "$0")" && pwd)"
app="$(dirname "$here")"
out="$here/out"
mkdir -p "$out"
csc="$(cygpath -u "$WINDIR")/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
refs="/reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:System.Web.Extensions.dll /reference:System.Numerics.dll"
"$csc" /nologo /target:winexe /optimize+ $refs /out:"$(cygpath -w "$out/ForeverUIManager.exe")" "$(cygpath -w "$app/ForeverUIManager.cs")"
"$csc" /nologo /target:exe /main:ForeverUIManager.Tests $refs /out:"$(cygpath -w "$out/Tests.exe")" "$(cygpath -w "$app/ForeverUIManager.cs")" "$(cygpath -w "$here/Tests.cs")"
"$out/Tests.exe" "$@"
