param(
    [int]$Port = 8080,
    [string]$ListenAddress = '127.0.0.1',
    [string]$ConfigPath = 'D:\.codexfile\work\leaderboard-api\local.env',
    [string]$RuntimeDirectory = 'D:\.codexfile\cache\leaderboard-api\venv'
)

$ErrorActionPreference = 'Stop'
$env:TEMP = 'D:\.codexfile\tmp'
$env:TMP = $env:TEMP
$env:PIP_CACHE_DIR = 'D:\.codexfile\cache\pip'
$env:PYTHONPYCACHEPREFIX = 'D:\.codexfile\cache\leaderboard-api\pycache'
$env:PYTHONUTF8 = '1'
New-Item -ItemType Directory -Force -Path $env:TEMP, $env:PIP_CACHE_DIR, $env:PYTHONPYCACHEPREFIX | Out-Null

$runtimePython = Join-Path $RuntimeDirectory 'Scripts\python.exe'
if (!(Test-Path -LiteralPath $runtimePython)) {
    $systemPython = (Get-Command python.exe -ErrorAction Stop).Source
    & $systemPython -m venv $RuntimeDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the Python environment' }
}
$requirements = Join-Path $PSScriptRoot 'requirements.txt'
$requirementsHash = (Get-FileHash -LiteralPath $requirements -Algorithm SHA256).Hash
$stampPath = Join-Path $RuntimeDirectory '.leaderboard-requirements'
if (!(Test-Path -LiteralPath $stampPath) -or (Get-Content -LiteralPath $stampPath -Raw).Trim() -ne $requirementsHash) {
    & $runtimePython -m pip install -r $requirements
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the API dependencies' }
    [System.IO.File]::WriteAllText($stampPath, $requirementsHash)
}

$ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
if (!(Test-Path -LiteralPath $ConfigPath)) {
    $stateDirectory = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
    $tokenBytes = New-Object byte[] 32
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($tokenBytes) } finally { $generator.Dispose() }
    $token = -join ($tokenBytes | ForEach-Object { $_.ToString('x2') })
    $databasePath = (Join-Path $stateDirectory 'leaderboard.sqlite3').Replace('\', '/')
    $configuration = "LEADERBOARD_DATABASE_URL=sqlite:///$databasePath`nLEADERBOARD_API_TOKEN=$token`n"
    [System.IO.File]::WriteAllText($ConfigPath, $configuration, [System.Text.UTF8Encoding]::new($false))
}
Write-Host "Local API: http://${ListenAddress}:$Port/docs"
Write-Host "Private configuration: $ConfigPath"
Write-Host 'Press Ctrl+C to stop.'
& $runtimePython -m uvicorn leaderboard.app:app --app-dir $PSScriptRoot --host $ListenAddress --port $Port --env-file $ConfigPath
if ($LASTEXITCODE -ne 0) { throw "API stopped with exit code $LASTEXITCODE" }
