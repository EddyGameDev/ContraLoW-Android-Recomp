# Build the recompiler (psxrecomp-game.exe) from the psxrecomp submodule.
#   pwsh -File tools\build-recompiler.ps1            (build if missing)
#   pwsh -File tools\build-recompiler.ps1 -Force     (rebuild)
# Adapted from dguillot-gh/psx-android tools/build-recompiler.ps1 (MIT).
# Uses the portable llvm-mingw C++ compiler (downloaded once into tools-cache\llvm-mingw,
# ~190 MB) and the Android SDK's CMake + Ninja. Nothing is installed into Windows.
param([switch]$Force)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "paths.ps1")
$src = Join-Path $FrameworkDir "recompiler"
$out = Join-Path $src "build-mingw"
$exe = Join-Path $out "psxrecomp-game.exe"
if ((Test-Path $exe) -and -not $Force) { Write-Host "OK   recompiler: $exe"; exit 0 }

# 1. llvm-mingw (the same release the psx-android builds use).
$llvmTag = "20260922"
if (-not (Test-Path (Join-Path $LlvmMingw "bin\clang++.exe"))) {
    $zip = Join-Path $ToolsCache "llvm-mingw.zip"
    New-Item -ItemType Directory -Force $ToolsCache | Out-Null
    Write-Host "Downloading the llvm-mingw C++ compiler (about 190 MB)..."
    Invoke-WebRequest "https://github.com/mstorsjo/llvm-mingw/releases/download/$llvmTag/llvm-mingw-$llvmTag-ucrt-x86_64.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive $zip $ToolsCache -Force
    Remove-Item $zip -Force
    Rename-Item (Join-Path $ToolsCache "llvm-mingw-$llvmTag-ucrt-x86_64") "llvm-mingw"
}
# 2. CMake + Ninja from the Android SDK.
$sdk = Find-Sdk
$cmakeBin = if ($sdk) { Join-Path $sdk "cmake\$CmakeVersion\bin" } else { "" }
if (-not $cmakeBin -or -not (Test-Path (Join-Path $cmakeBin "cmake.exe"))) { Write-Host "FAIL: no SDK CMake $CmakeVersion (set ANDROID_HOME)"; exit 1 }
$env:PATH = (Join-Path $LlvmMingw "bin") + ";" + $cmakeBin + ";" + $env:PATH

# 3. Configure + build. The newer libc++ in llvm-mingw no longer pulls standard headers in
#    transitively, which some of the recompiler's sources rely on: force-include them.
$cxxFlags = "-include cstdlib -include cstdio -include cstring -include cstdint -include exception " +
            "-include algorithm -include functional -include memory -include string -include vector " +
            "-include utility -include limits"
Write-Host "Building the recompiler (about 5-10 minutes)..."
# A build folder copied from elsewhere remembers its old paths; configure afresh in that case.
$cache = Join-Path $out "CMakeCache.txt"
if (Test-Path $cache) {
    $cachedSrc = (Select-String -Path $cache -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=(.*)$' | Select-Object -First 1).Matches.Groups[1].Value
    if ($cachedSrc -and ($cachedSrc.TrimEnd('/') -ne ($src -replace '\\', '/').TrimEnd('/'))) {
        Write-Host "The recompiler's build folder was set up at $cachedSrc; configuring it afresh here"
        Remove-Item $cache -Force
        Remove-Item (Join-Path $out "CMakeFiles") -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Fail-WithLog([string]$what, [string]$log) {
    Write-Host "FAIL: $what (see $log). Last lines:"
    Get-Content $log -Tail 25 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
    exit 1
}
$cfgLog = Join-Path $src "build-mingw-configure.log"; $buildLog = Join-Path $src "build-mingw-build.log"
& cmake -S $src -B $out -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ `
    -DPSXRECOMP_ENABLE_CHD=OFF "-DCMAKE_CXX_FLAGS=$cxxFlags" *> $cfgLog
if ($LASTEXITCODE -ne 0) { Fail-WithLog "configure" $cfgLog }
& cmake --build $out --target psxrecomp-game *> $buildLog
if ($LASTEXITCODE -ne 0) { Fail-WithLog "build" $buildLog }
if (-not (Test-Path $exe)) { Fail-WithLog "output missing" $buildLog }
Write-Host "OK   recompiler: $exe"
exit 0
