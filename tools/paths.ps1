# Shared locations for this game's build scripts. Dot-source it:
#   . (Join-Path $PSScriptRoot "paths.ps1")
# Everything downloaded or built lands in tools-cache\ (gitignored) or build
# output folders; nothing is installed into Windows.
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ToolsCache = Join-Path $RepoRoot "tools-cache"
$FrameworkDir = Join-Path $RepoRoot "psxrecomp"          # the engine submodule
$LlvmMingw = Join-Path $ToolsCache "llvm-mingw"          # portable C++ compiler for the recompiler
$GradleHome = Join-Path $ToolsCache "gradle"             # Gradle's download cache
$NdkVersion = "28.2.13676358"
$CmakeVersion = "3.22.1"

function Find-Java {
    $c = @()
    if ($env:JAVA_HOME) { $c += Join-Path $env:JAVA_HOME "bin\java.exe" }
    foreach ($p in "C:\Program Files\Microsoft\jdk-17*", "C:\Program Files\Microsoft\jdk-21*", "C:\Program Files\Eclipse Adoptium\jdk-17*",
                   "C:\Program Files\Eclipse Adoptium\jdk-21*", "C:\Program Files\Java\jdk-17*", "C:\Program Files\Android\Android Studio\jbr") {
        Get-Item $p -ErrorAction SilentlyContinue | ForEach-Object { $c += Join-Path $_.FullName "bin\java.exe" }
    }
    $c | Where-Object { Test-Path $_ } | Select-Object -First 1
}

# The PC's Android SDK (ANDROID_HOME / ANDROID_SDK_ROOT / Android Studio's default).
function Find-Sdk {
    @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA "Android\Sdk")) |
        Where-Object { $_ -and (Test-Path (Join-Path $_ "platform-tools")) } | Select-Object -First 1
}

# Python 3 for the recompiler and helper tools (standard library only).
function Find-Python {
    foreach ($n in "python", "python3") {
        $c = Get-Command $n -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1
        if ($c) { return $c.Source }
    }
    return $null
}
