# Build this game's Android APK (launcher-style: the disc is selected on the phone,
# nothing from the disc is embedded).
#   pwsh -File tools\build-apk.ps1 [-Play]
# -Play builds the "play" version (no debug server, ~20% faster).
# Adapted from dguillot-gh/psx-android tools/build.ps1 (MIT).
param([switch]$Play)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "paths.ps1")
$android = Join-Path $RepoRoot "android"
if (-not (Test-Path (Join-Path $android "app\build.gradle"))) { Write-Host "FAIL: no Android app in $android"; exit 1 }

# --- Java ------------------------------------------------------------------
$java = Find-Java
if (-not $java) { Write-Host "FAIL: no Java found (install Java 17+ or Android Studio)"; exit 1 }
Write-Host "Java: $java"

# --- Android SDK -----------------------------------------------------------
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA "Android\Sdk")) |
    Where-Object { $_ -and (Test-Path (Join-Path $_ "ndk\$NdkVersion")) -and (Test-Path (Join-Path $_ "cmake\$CmakeVersion")) } |
    Select-Object -First 1
if (-not $sdk) { Write-Host "FAIL: no Android SDK with NDK $NdkVersion and CMake $CmakeVersion (set ANDROID_HOME)"; exit 1 }
Write-Host "SDK:  $sdk"
$env:GRADLE_USER_HOME = $GradleHome

# --- local.properties --------------------------------------------------------
$props = Join-Path $android "local.properties"
$sdkLine = "sdk.dir=" + $sdk.Replace("\", "/")
if (-not (Test-Path $props) -or -not (Select-String -Path $props -SimpleMatch $sdkLine -Quiet)) {
    Set-Content -Path $props -Value $sdkLine -Encoding utf8NoBOM
    Write-Host "Wrote $props"
}

# --- Per-game BIOS -------------------------------------------------------------
# The app bundles the free OpenBIOS (MIT) from the framework. A game that needs Sony's
# BIOS names it in android-bios.txt (one line, a file in psxrecomp\bios\): it is copied
# into the app and written into game.toml.in. Such an APK contains Sony's BIOS: for your
# own phone only, not for sharing.
$assets = Join-Path $android "app\src\main\assets"
$tomlIn = Join-Path $assets "game.toml.in"
$biosWant = Join-Path $RepoRoot "android-bios.txt"
$biosName = if (Test-Path $biosWant) { (Get-Content $biosWant -TotalCount 1).Trim() } else { "" }
Get-ChildItem (Join-Path $assets "bios") -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin "openbios.bin", "OpenBIOS.LICENSE", $biosName } | Remove-Item -Force
if ($biosName) {
    $src = Join-Path $FrameworkDir "bios\$biosName"
    if (-not (Test-Path $src)) { Write-Host "FAIL: this game needs $biosName (android-bios.txt), but $src is missing. Copy your own $biosName into that folder."; exit 1 }
    New-Item -ItemType Directory -Force (Join-Path $assets "bios") | Out-Null
    Copy-Item $src (Join-Path $assets "bios\$biosName") -Force
    Write-Host "BIOS: $biosName (from android-bios.txt)"
}
if (Test-Path $tomlIn) {
    $want = if ($biosName) { "bios/$biosName" } else { "bios/openbios.bin" }
    $t = Get-Content $tomlIn -Raw
    $n = [regex]::Replace($t, '(?m)^path = "bios/[^"]*"', "path = `"$want`"")
    if ($n -ne $t) { Set-Content -Path $tomlIn -Value $n -NoNewline -Encoding utf8NoBOM }
}

# --- Codegen hash header -------------------------------------------------------
# Gradle's stageGameOverlays reads it before the native build would write it.
$py = Find-Python
$recExe = Join-Path $FrameworkDir "recompiler\build-mingw\psxrecomp-game.exe"
if ($py -and (Test-Path $recExe)) {
    $hout = @(& $py (Join-Path $PSScriptRoot "codegen_hash.py") $FrameworkDir --recompiler $recExe 2>&1)
    $hc = $LASTEXITCODE
    if ($hc -eq 2) { Write-Host "FAIL: $($hout -join ' ') - rebuild with tools\build-recompiler.ps1 -Force"; exit 2 }
    if ($hc -ne 0) { Write-Host "WARNING: codegen hash header: $($hout -join ' ')" }
}

# --- SDL3 source: download once, pinned by SHA-256 from the framework's manifest ---
$manifest = Join-Path $FrameworkDir "third_party\deps.manifest"
$sdlLine = if (Test-Path $manifest) { Get-Content $manifest | Where-Object { $_ -match '^SDL3\s' } | Select-Object -First 1 }
if ($sdlLine) {
    $f = $sdlLine -split '\s+'          # name, file, sha256, url
    $deps = Join-Path $ToolsCache "deps"
    $sdlDir = Join-Path $deps ($f[1] -replace '\.tar\.gz$', '')
    if (-not (Test-Path (Join-Path $sdlDir "CMakeLists.txt"))) {
        New-Item -ItemType Directory -Force $deps | Out-Null
        $tgz = Join-Path $deps $f[1]
        for ($try = 1; $try -le 5 -and -not (Test-Path $tgz); $try++) {
            Write-Host "Downloading $($f[1]) once for all builds (try $try)..."
            try { Invoke-WebRequest $f[3] -OutFile $tgz -UseBasicParsing } catch { Remove-Item $tgz -ErrorAction SilentlyContinue; Start-Sleep -Seconds (15 * $try) }
        }
        if ((Test-Path $tgz) -and (Get-FileHash $tgz -Algorithm SHA256).Hash -eq $f[2].ToUpper()) {
            & "$env:SystemRoot\System32\tar.exe" -xzf $tgz -C $deps
        } else {
            Remove-Item $tgz -ErrorAction SilentlyContinue
            Write-Host "NOTE: could not get a verified SDL3 copy; the build will try to download it itself"
        }
    }
    if (Test-Path (Join-Path $sdlDir "CMakeLists.txt")) { $env:PSX_SDL3_SOURCE_DIR = $sdlDir; Write-Host "SDL3 from $sdlDir (no download)" }
}

# --- Gradle ------------------------------------------------------------------
$wrapper = Join-Path $android "gradle\wrapper\gradle-wrapper.jar"
$gradleArgs = @("-classpath", $wrapper, "org.gradle.wrapper.GradleWrapperMain", "--no-daemon", ":app:assembleDebug")
if ($Play) { $gradleArgs += "-PpsxPlayBuild" }
# A shared debug signing key (tools-cache\debug.keystore, or PSX_KEYSTORE) keeps updates
# installable across rebuilds; without it Gradle uses this PC's own debug key.
$sharedKey = if ($env:PSX_KEYSTORE) { $env:PSX_KEYSTORE } else { Join-Path $ToolsCache "debug.keystore" }
if (Test-Path $sharedKey) {
    $gradleArgs += @("-Pandroid.injected.signing.store.file=$sharedKey", "-Pandroid.injected.signing.store.password=android",
                     "-Pandroid.injected.signing.key.alias=androiddebugkey", "-Pandroid.injected.signing.key.password=android")
    Write-Host "Signing with the shared key ($sharedKey)"
} else {
    Write-Host "NOTE: no shared signing key; using this PC's own debug key"
}
Write-Host "Building (the first build takes 30-60 minutes; later ones are much faster)..."
$log = Join-Path $RepoRoot "build-android.log"

$job = Start-Job -ScriptBlock {
    param($java, $gradleArgs, $log, $dir, $gradleHome)
    Set-Location $dir
    $env:GRADLE_USER_HOME = $gradleHome
    & $java @gradleArgs *> $log
    $LASTEXITCODE
} -ArgumentList $java, $gradleArgs, $log, $android, $GradleHome

$started = Get-Date
while ($job.State -eq "Running") {
    Wait-Job $job -Timeout 60 | Out-Null
    if ($job.State -ne "Running") { break }
    $clang = @(Get-Process clang -ErrorAction SilentlyContinue)
    $what = if ($clang.Count) { "$($clang.Count) clang compiling" } else { "Gradle working (no compiler running right now)" }
    $ninja = Get-ChildItem (Join-Path $android "app\.cxx\Debug\*\arm64-v8a") -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ninja -and (Test-Path (Join-Path $ninja.FullName ".ninja_log")) -and (Test-Path (Join-Path $ninja.FullName "build.ninja"))) {
        $total = (Select-String -Path (Join-Path $ninja.FullName "build.ninja") -Pattern '^build \S+\.o:').Count
        $done = @(Get-Content (Join-Path $ninja.FullName ".ninja_log") | ForEach-Object { ($_ -split "`t")[3] } |
                  Where-Object { $_ -like "*.o" } | Sort-Object -Unique).Count
        if ($done -ge $total -and $clang.Count -eq 0) { $what = "all $total files compiled, linking (can take several minutes)" }
        else { $what += ", $done/$total files compiled" }
    }
    Write-Host ("[{0}] BUILD: still working, {1} min so far: {2}" -f (Get-Date -Format "HH:mm:ss"), [int]((Get-Date) - $started).TotalMinutes, $what)
}
$code = Receive-Job $job | Select-Object -Last 1
Remove-Job $job
if ($null -eq $code) { $code = 1 }
if ($code -ne 0) {
    Write-Host "FAIL: Gradle build failed (exit $code). Last lines of $log :"
    Get-Content $log -Tail 25 | ForEach-Object { Write-Host "  $_" }
    exit 1
}
$apk = Join-Path $android "app\build\outputs\apk\debug\app-debug.apk"
if (-not (Test-Path $apk)) { Write-Host "FAIL: build said OK but $apk is missing"; exit 1 }
$apkDir = Join-Path $RepoRoot "apk"
New-Item -ItemType Directory -Force $apkDir | Out-Null
$kind = if ($Play) { "play" } else { "debug" }
$copy = Join-Path $apkDir ("contralow_recomp-{0}-{1}.apk" -f $kind, (Get-Date -Format "yyyyMMdd-HHmm"))
Copy-Item $apk $copy
Write-Host "OK: built $copy"
exit 0
