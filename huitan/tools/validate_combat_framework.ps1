#requires -Version 7.0
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [string]$LogDirectory = 'D:\.codexfile\work\combat-framework-checks'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$engine = (Resolve-Path -LiteralPath $GodotPath).Path
$projectRoot = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
New-Item -ItemType Directory -Force -Path 'D:\.codexfile\tmp' | Out-Null
$previousTemp = $env:TEMP
$previousTmp = $env:TMP

# Functional fixtures only. No population benchmark, frame timing or GPU capture.
$checks = @(
    @{ Name = 'test_combat_extension_framework'; Marker = 'COMBAT_EXTENSION_FRAMEWORK.*"failures":\[\]' },
    @{ Name = 'test_land_water_support'; Marker = 'LAND_WATER_SUPPORT.*"failures":\[\]' },
    @{ Name = 'test_pursuit_query_batch'; Marker = 'PURSUIT_QUERY_BATCH.*"failures":\[\]' },
    @{ Name = 'test_spawn_sync_gate'; Marker = 'Spawn synchronization gate: \d+ checks, 0 failures' },
    @{ Name = 'test_local_spawn_safety'; Marker = 'Local spawn safety: \d+ checks, 0 failures' },
    @{ Name = 'test_attack_ray_clearance'; Marker = 'Player basic sword: \d+ checks, 0 failures' },
    @{ Name = 'test_eccentric_ricochet'; Marker = 'Aim path preview: \d+ checks, 0 failures' },
    @{ Name = 'test_preview_query_view'; Marker = '"failures":0' }
)

try {
    $env:TEMP = 'D:\.codexfile\tmp'
    $env:TMP = $env:TEMP
    foreach ($check in $checks) {
        $logPath = Join-Path $LogDirectory ($check.Name + '.log')
        & $engine --headless --path $projectRoot --fixed-fps 60 --script ('tests/' + $check.Name + '.gd') *> $logPath
        $result = $LASTEXITCODE
        $output = Get-Content -LiteralPath $logPath -Raw
        if ($result -ne 0 -or $output -match '(?m)^ERROR:|SCRIPT ERROR:|(?m)^FAIL:' -or $output -notmatch $check.Marker) {
            Get-Content -LiteralPath $logPath -Tail 20 | Write-Output
            throw ('Functional check failed: ' + $check.Name + '; log: ' + $logPath)
        }
        if ($output -match '(?m)^WARNING:') {
            Write-Warning ($check.Name + ' completed with warnings; inspect ' + $logPath)
        }
        Write-Output ('PASS ' + $check.Name)
    }
    Write-Output ('Combat framework functional checks passed. Logs: ' + $LogDirectory)
}
finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}
