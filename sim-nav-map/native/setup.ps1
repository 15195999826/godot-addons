# One-time machine setup for building the sim-nav-map native backend:
# clones godot-cpp at the pinned commit and dumps extension_api.json from the
# Godot binary on PATH. Build afterwards with the scons lines in SConstruct.
$ErrorActionPreference = "Stop"

# v10 master; rc1 breaks against the 4.7 API dump (issue #1941: 4.7's new
# UINT8_MAX/INT64_MIN global constants collide with stdint macros; fixed by
# 67a0b191 after rc1). Bump deliberately, then rebuild + rerun native smokes.
$pin = "ba0edfed90512ec64aba51d4295a3e7e30112f86"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cpp = Join-Path $root "godot-cpp"

if (-not (Test-Path (Join-Path $cpp ".git"))) {
    git init $cpp
    git -C $cpp remote add origin https://github.com/godotengine/godot-cpp.git
}
git -C $cpp fetch --depth 1 origin $pin
git -C $cpp checkout -q FETCH_HEAD
Write-Host "godot-cpp pinned at $(git -C $cpp rev-parse --short HEAD)"

# compatibility_minimum = "4.7" in simnav_native.gdextension is bound to this
# dump — a different Godot on PATH would silently bake the wrong API surface.
# cmd /c wrapper: godot.exe is a GUI-subsystem binary — direct invocation in a
# PowerShell script context returns before its console output is capturable.
$godotVersion = ((& cmd /c "godot --version 2>&1") -join "").Trim()
if ($godotVersion -notmatch "^4\.7\.") {
    throw "Godot on PATH is '$godotVersion', need 4.7.* (extension_api.json must match compatibility_minimum)"
}

Push-Location $root
try {
    godot --headless --dump-extension-api
    if (-not (Test-Path (Join-Path $root "extension_api.json"))) {
        throw "godot --dump-extension-api produced no extension_api.json in $root"
    }
    Write-Host "extension_api.json dumped from $godotVersion"
} finally {
    Pop-Location
}
