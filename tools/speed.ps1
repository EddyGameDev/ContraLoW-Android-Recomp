# Pre-compile the game's overlay code for the phone ("AOT overlays") — the speed pass.
#   pwsh -File tools\speed.ps1 [-NoPhone] [-MaxMinutes 45]
# PS1 games load extra code from the disc while they run. Without this step that code runs on
# the slow interpreter (first boot: tens of fps). Steps (everything under build-android-overlays\):
#  1. disc_captures.json : code found on the disc itself (framework's extract_generic.py).
#  2. play_captures.json : code the phone recorded while the game was played (pulled read-only
#     via run-as; merged with earlier pulls).
#  3. aot_all.json       : both merged; split into one group per CPU core (par\gNN.json).
#  4. compile_overlays.py per group, in parallel, with the NDK's clang (minutes to ~30 min).
#     At the time limit the unfinished groups are stopped; everything finished is used, and
#     the next run resumes where this one stopped (finished pieces are kept in par\out_gNN).
#  5. cache\<game id>\gcc\linux-arm64\ : the result. The -Play APK build bundles it.
# Adapted from dguillot-gh/psx-android tools/speed.ps1 (MIT); pull-captures inlined.
param([switch]$NoPhone, [int]$MaxMinutes = 45, [string]$Package = "com.psxrecomp.contralow")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "paths.ps1")

$py = Find-Python
$ndk = Find-Ndk
if (-not $py) { Write-Host "SPEED: FAIL no Python"; exit 1 }
if (-not $ndk) { Write-Host "SPEED: FAIL no NDK $NdkVersion (set ANDROID_HOME)"; exit 1 }
$tomlIn = Join-Path $RepoRoot "android\app\src\main\assets\game.toml.in"
if (-not (Test-Path $tomlIn)) { Write-Host "SPEED: FAIL no Android app"; exit 1 }
$gameId = if ((Get-Content $tomlIn -Raw) -match '(?m)^id\s*=\s*"([^"]+)"') { $Matches[1] } else { "" }
if (-not $gameId) { Write-Host "SPEED: FAIL no game id in $tomlIn"; exit 1 }

$Groups = [int]$env:NUMBER_OF_PROCESSORS - 2
if ($Groups -gt 12) { $Groups = 12 }
if ($Groups -lt 2) { $Groups = 2 }

$recompiler = Join-Path $FrameworkDir "recompiler\build-mingw\psxrecomp-game.exe"
$W = Join-Path $RepoRoot "build-android-overlays"
New-Item -ItemType Directory -Force $W | Out-Null
$disc = Join-Path $W "disc_captures.json"
$play = Join-Path $W "play_captures.json"
$all = Join-Path $W "aot_all.json"

# 1. From the disc. A failure here is not fatal: play captures may still cover the game.
Push-Location $RepoRoot
& $py psxrecomp\tools\aot_overlay_spike\extract_generic.py --game-toml game.toml --recompiler $recompiler --out $disc --tmp (Join-Path $W "tmp") *> (Join-Path $W "extract.log")
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Write-Host "SPEED: NOTE finding code on the disc failed (see $W\extract.log); using play captures only"; Remove-Item $disc -ErrorAction SilentlyContinue }

# 2. From play on the phone (read-only pull; merged with what earlier runs pulled). Exit 2 = none yet.
if (-not $NoPhone) {
    $adb = Find-Adb
    $new = Join-Path $W "play_new.json"
    & $adb shell run-as $Package ls files/overlay_captures.json *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "SPEED: no play captures on the phone yet (play the game a little first)"
    } else {
        & $adb exec-out run-as $Package cat files/overlay_captures.json > $new
        & $py (Join-Path $PSScriptRoot "captures.py") merge --out $play $play $new
        Remove-Item $new -ErrorAction SilentlyContinue
    }
}

# 3. Merge, and stop early when there is nothing new.
& $py (Join-Path $PSScriptRoot "captures.py") merge --out $all $disc $play
$count = @(& $py -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" $all)[0]
$digest = @(& $py (Join-Path $PSScriptRoot "captures.py") digest $all)[0]
$hash = (@(& $recompiler --codegen-hash) -join "").Trim()
$cache = Join-Path $W "cache\$gameId\gcc\linux-arm64"
$stamp = Join-Path $W "compiled.digest"
Write-Host "SPEED: $count piece(s) of game code to pre-compile (disc + play), codegen $hash"
if ([int]$count -eq 0) { Write-Host "SPEED: nothing found yet. Play the game a little on the phone, then run again."; exit 0 }
$have = @(Get-ChildItem $cache -Directory -Filter "cg*_$($hash)_*" -ErrorAction SilentlyContinue)
if ($have.Count -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq "$digest $hash")) {
    Write-Host "SPEED: already pre-compiled (no new code since the last run)"; exit 0
}

# The phone-side config the shards are keyed to (the app's game.toml.in with a placeholder disc).
$phoneToml = Join-Path $W "phone-game.toml"
$lines = Get-Content $tomlIn | ForEach-Object {
    if ($_ -match '^\s*@@DISC1@@') { '  "disc/game.cue",' } elseif ($_ -match '@@DISC\d+@@') { } else { $_ } }
Set-Content -Path $phoneToml -Value $lines -Encoding utf8NoBOM

# 4. Compile, one process per group.
$par = Join-Path $W "par"
& $py (Join-Path $PSScriptRoot "captures.py") split --in $all --groups $Groups --outdir $par
$procs = @()
foreach ($g in Get-ChildItem $par -Filter "g??.json" | Sort-Object Name) {
    $n = $g.BaseName
    $a = @("psxrecomp\tools\compile_overlays.py", "--captures", "`"$($g.FullName)`"", "--game-toml", "`"$phoneToml`"",
           "--recompiler", "`"$recompiler`"", "--runtime-include", "psxrecomp\runtime\include",
           "--out-dir", "`"$(Join-Path $par "out_$n")`"", "--gcc", "`"$(Join-Path $ndk 'bin\clang.exe')`"",
           "--target-os", "android", "--target-arch", "arm64", "--android-sysroot", "`"$(Join-Path $ndk 'sysroot')`"",
           "--cps", "--jobs", "1")
    $procs += Start-Process -FilePath $py -ArgumentList $a -WorkingDirectory $RepoRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $par "$n.log") -RedirectStandardError (Join-Path $par "$n.err.log")
}
Write-Host "SPEED: compiling in $($procs.Count) parallel group(s) (minutes to about 30 min, stops at $MaxMinutes min)"
$started = Get-Date
$timedOut = $false
while (@($procs | Where-Object { -not $_.HasExited }).Count) {
    Start-Sleep -Seconds 60
    $left = @($procs | Where-Object { -not $_.HasExited }).Count
    $so = @(Get-ChildItem $par -Recurse -Filter *.so -ErrorAction SilentlyContinue).Count
    $mins = [int]((Get-Date) - $started).TotalMinutes
    Write-Host ("SPEED: still compiling, {0} min so far: {1} of {2} groups finished, {3} pieces compiled" -f $mins, ($procs.Count - $left), $procs.Count, $so)
    if ($left -and $mins -ge $MaxMinutes) {
        Write-Host "SPEED: time limit ($MaxMinutes min) reached with $left group(s) still going; using what is finished, the next run continues"
        foreach ($p in @($procs | Where-Object { -not $_.HasExited })) { taskkill /T /F /PID $p.Id 2>&1 | Out-Null }
        Start-Sleep -Seconds 3
        $timedOut = $true
        break
    }
}
$ok = 0; $bad = 0
foreach ($l in Get-ChildItem $par -Filter "g??.log") {
    foreach ($r in Select-String -Path $l.FullName -Pattern 'PSX_SHARD_RESULT ok=(\d+) failed=(\d+)') {
        $ok += [int]$r.Matches[0].Groups[1].Value; $bad += [int]$r.Matches[0].Groups[2].Value
    }
}

# 5. Merge the groups into the cache the app build bundles (rebuilt fresh each time).
if (Test-Path (Join-Path $W "cache\$gameId")) { Remove-Item (Join-Path $W "cache\$gameId") -Recurse -Force }
New-Item -ItemType Directory -Force $cache | Out-Null
foreach ($o in Get-ChildItem $par -Directory -Filter "out_g*") {
    $src = Join-Path $o.FullName "$gameId\gcc\linux-arm64"
    foreach ($d in Get-ChildItem $src -Directory -Filter "cg*_$($hash)_*" -ErrorAction SilentlyContinue) {
        $dst = Join-Path $cache $d.Name
        New-Item -ItemType Directory -Force $dst | Out-Null
        foreach ($f in Get-ChildItem $d.FullName -Filter *.so) {
            $r = $f.FullName.Substring(0, $f.FullName.Length - 3) + ".ranges"   # x.so -> x.ranges
            if ($f.Name.StartsWith(".") -or -not (Test-Path $r) -or (Test-Path "$($f.FullName).pair-txn.json")) { continue }
            Copy-Item $f.FullName, $r $dst -Force
        }
    }
}
$so = @(Get-ChildItem $cache -Recurse -Filter *.so).Count
if ($so -eq 0) { Write-Host "SPEED: FAIL nothing compiled ($bad failed; logs in $par)"; exit 1 }
if ($timedOut) {
    Write-Host "SPEED: partly done, $so compiled pieces ready; rerun to finish the rest (it resumes)"
    exit 0
}
Set-Content $stamp "$digest $hash"
Get-ChildItem $par -Directory -Filter "out_g*" | Remove-Item -Recurse -Force
$note = if ($bad) { ", $bad failed (those parts stay on the interpreter; logs in $par)" } else { "" }
Write-Host "SPEED: done, $so compiled pieces ready ($ok ok$note)"
exit 0
