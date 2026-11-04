# Regenerate the game's C code from your disc with the recompiler.
#   pwsh -File tools\regen.ps1
# Reads game.toml (which points at disc\<cue>) and writes generated\.
# The disc itself is never modified; generated\ is gitignored (disc-derived).
# Adapted from dguillot-gh/psx-android go.ps1's REGEN step (MIT).
param([switch]$Force)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "paths.ps1")

$exe = Join-Path $FrameworkDir "recompiler\build-mingw\psxrecomp-game.exe"
if (-not (Test-Path $exe)) {
    Write-Host "RECOMPILER: not built yet; building it first"
    & (Join-Path $PSScriptRoot "build-recompiler.ps1")
    if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: could not build the recompiler"; exit 1 }
}

# The codegen hash header must exist and match before the build (Gradle's
# stageGameOverlays reads it before CMake would write it).
$py = Find-Python
if ($py) {
    $hout = @(& $py (Join-Path $PSScriptRoot "codegen_hash.py") $FrameworkDir --recompiler $exe 2>&1)
    $hc = $LASTEXITCODE
    if ($hc -eq 2) { Write-Host "FAIL: $($hout -join ' ') - rebuild with tools\build-recompiler.ps1 -Force"; exit 2 }
    if ($hc -ne 0) { Write-Host "WARNING: could not write the codegen hash header: $($hout -join ' ')" }
    else { Write-Host "Codegen hash: $hout" }
} else {
    Write-Host "WARNING: no Python found; codegen hash header not checked"
}

$marker = Join-Path $RepoRoot ".regenerated"
if ((Test-Path $marker) -and -not $Force -and (Get-Item $exe).LastWriteTime -le (Get-Item $marker).LastWriteTime) {
    Write-Host "REGEN: already done (use -Force to redo)"
    exit 0
}
Write-Host "REGEN: regenerating game code (log: regen.log)"
Push-Location $RepoRoot
& $exe --config game.toml *> regen.log
$code = $LASTEXITCODE
Pop-Location
if ($code -eq 0) {
    Set-Content -Path $marker -Value (Get-Date -Format o) -Encoding utf8NoBOM
    $wrote = Select-String (Join-Path $RepoRoot "regen.log") -Pattern 'Wrote (\d+) shards .* for (\S+)' | Select-Object -First 1
    if ($wrote) { Write-Host "REGEN: done - $($wrote.Matches[0].Value)" } else { Write-Host "REGEN: done" }
} else {
    Write-Host "REGEN: FAILED (exit $code). Last lines of regen.log:"
    Get-Content (Join-Path $RepoRoot "regen.log") -Tail 25 | ForEach-Object { Write-Host "  $_" }
}
exit $code
