param(
    [Parameter(Mandatory)][string]$GodotPath,
    [string]$GodotCppPath = 'D:/.codexfile/cache/godot-cpp/native-swarm-20261017',
    [string]$BuildDirectory = 'D:/.codexfile/work/native-swarm-20261017/build',
    [string]$PythonPath = ''
)
$ErrorActionPreference = 'Stop'
if (-not $PythonPath) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCommand) { throw 'Pass -PythonPath <Python 3 executable> or add Python 3 to PATH.' }
    $PythonPath = $pythonCommand.Source
}
if (-not (Test-Path -LiteralPath $PythonPath)) { throw "Missing Python executable: $PythonPath" }
$pinnedCommit = '2bb1acf6f8ae1ce96ac7b9ba3a10b499c59c49ec'
if (-not (Test-Path -LiteralPath "$GodotCppPath/CMakeLists.txt")) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $GodotCppPath) | Out-Null
    & git clone https://github.com/godotengine/godot-cpp.git $GodotCppPath
    if ($LASTEXITCODE -ne 0) { throw 'godot-cpp clone failed' }
    & git -C $GodotCppPath checkout --detach $pinnedCommit
    if ($LASTEXITCODE -ne 0) { throw 'godot-cpp checkout failed' }
}
$actualCommit = & git -C $GodotCppPath rev-parse HEAD
if ($actualCommit -ne $pinnedCommit) { throw "Expected godot-cpp $pinnedCommit; found $actualCommit" }
New-Item -ItemType Directory -Force -Path $BuildDirectory | Out-Null
Push-Location $BuildDirectory
try {
    & $GodotPath --headless --dump-extension-api
    if ($LASTEXITCODE -ne 0) { throw 'Engine API dump failed' }
} finally { Pop-Location }
$apiPath = Join-Path $BuildDirectory 'extension_api.json'
$api = Get-Content -LiteralPath $apiPath -Raw | ConvertFrom-Json
if ($api.header.version_major -ne 4 -or $api.header.version_minor -ne 7 -or $api.header.version_patch -ne 2 -or $api.header.precision -ne 'single') {
    throw 'This prototype is validated against Godot 4.7.2 single precision only.'
}
& cmake -S $PSScriptRoot -B $BuildDirectory -G 'Visual Studio 17 2022' -A x64 "-DGODOT_CPP_SOURCE=$GodotCppPath" "-DGODOTCPP_CUSTOM_API_FILE=$apiPath" "-DPython3_EXECUTABLE=$PythonPath"
if ($LASTEXITCODE -ne 0) { throw 'Native configure failed' }
& cmake --build $BuildDirectory --config Release --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
$binary = Get-Item -LiteralPath "$PSScriptRoot/bin/hd2d_swarm.dll"
Get-FileHash -LiteralPath $binary.FullName -Algorithm SHA256
