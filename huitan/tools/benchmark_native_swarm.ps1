param(
    [Parameter(Mandatory)][string]$GodotPath,
    [string]$OutputDirectory = 'D:/.codexfile/work/native-swarm-20261017/comparison',
    [ValidateRange(1,2)][int]$Pairs = 2,
    [ValidateRange(0,4)][int]$Storm = 0,
    [switch]$CollectRejectedDiagnostics
)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$nativeDirectory = Join-Path $projectDirectory 'native/swarm'
$dll = Join-Path $nativeDirectory 'bin/hd2d_swarm.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Build native/swarm/build.ps1 first.' }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$files = @(Get-ChildItem -LiteralPath "$projectDirectory/scripts","$projectDirectory/data","$projectDirectory/scenes","$projectDirectory/tools",$nativeDirectory -File -Recurse | Where-Object Extension -in @('.gd','.tres','.tscn','.gdshader','.cpp','.json','.gdextension','.ps1','.dll')) + @(Get-Item -LiteralPath "$projectDirectory/project.godot")
$hashes = @{}
foreach ($file in $files) { $hashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath "$OutputDirectory/source-manifest.json"
$sequence = if ($Pairs -eq 1) { @('script','native') } else { @('script','native','native','script') }
$runs = @()
$rejected = @()
$serial = 0
foreach ($backend in $sequence) {
    $serial++
    $label = "$serial-128-$backend"
    $json = "$OutputDirectory/$label.json"
    $log = "$OutputDirectory/$label.log"
    $arguments = @('--headless','--fixed-fps','60','--path',$projectDirectory,'--audio-driver','Dummy','--script','res://tools/benchmark_native_queries.gd','--','--count=128','--native-queries','--with-native-prototype',"--storm=$Storm","--output=$json")
    if ($backend -eq 'native') { $arguments += '--native-swarm' }
    Write-Output "RUN $label"
    & $GodotPath @arguments *> $log
    $exitCode = $LASTEXITCODE
    $engineError = (Get-Content -LiteralPath $log -Raw) -match '(?m)^(?:SCRIPT ERROR:|ERROR:|WARNING:.*(?:leaked|still in use))'
    if ($engineError -or -not (Test-Path -LiteralPath $json)) {
        Get-Content -LiteralPath $log -Tail 20
        throw "Native comparison failed: $label exit=$exitCode"
    }
    $data = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
    $accepted = $exitCode -eq 0 -and $data.failures.Count -eq 0
    $runs += @{label=$label;backend=$backend;json=$json;log=$log;accepted=$accepted;failures=@($data.failures)}
    $runs | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$OutputDirectory/runs.json"
    Write-Output "DONE $label hits=$($data.hits) flight=$($data.flight_hits) turns=$($data.deflections)"
    if (-not $accepted) {
        $rejected += $label
        if (-not $CollectRejectedDiagnostics) { throw "Behaviour gates failed: $label. No performance acceptance; see runs.json." }
        Write-Output "REJECTED $label; collecting diagnostics only"
    }
}
foreach ($path in $hashes.Keys) {
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hashes[$path]) { throw "Source changed during comparison: $path" }
}
Write-Output "SOURCE VERIFIED $($hashes.Count) files, including native DLL"
$reference = Get-Content -LiteralPath $runs[0].json -Raw | ConvertFrom-Json
$mismatches = @()
foreach ($run in $runs | Select-Object -Skip 1) {
    $data = Get-Content -LiteralPath $run.json -Raw | ConvertFrom-Json
    foreach ($key in @('spawn_instance_ids','spawn_layout_sha256','behaviour','hits','flight_hits','strikes','deflections','wall_bounces','storm_hits','flying_ticks','preview_frames','moved_over_10cm')) {
        $expected = $reference.$key | ConvertTo-Json -Depth 30 -Compress
        $actual = $data.$key | ConvertTo-Json -Depth 30 -Compress
        if ($expected -cne $actual) { $mismatches += "$($run.label):$key" }
    }
}
$summary = @{count=128;accepted=($rejected.Count -eq 0 -and $mismatches.Count -eq 0);rejected=$rejected;behaviour_mismatches=$mismatches;runs=$runs}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$OutputDirectory/validation.json"
if (-not $summary.accepted) { throw 'Comparison rejected. Timing in these runs is diagnostic only; see validation.json.' }
Write-Output 'BEHAVIOUR VERIFIED; all comparison gates passed'
