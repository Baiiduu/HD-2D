param(
    [ValidateSet('core', 'regression', 'native', 'render', 'all')]
    [string]$Suite = 'regression',
    [string]$GodotPath = $env:GODOT_BIN,
    [string]$OutputDirectory = 'D:/.codexfile/work/godot-tests',
    [ValidateRange(5, 600)][int]$TimeoutSeconds = 120,
    [string[]]$Test,
    [switch]$UseProjectSystemSwitches,
    [switch]$List,
    [switch]$FailFast
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$groups = @{
    # Optional: requires a locally built native/swarm DLL; ordinary regression
    # remains runnable on a fresh checkout without the prototype toolchain.
    native = @('test_native_swarm_kernel', 'test_native_swarm_movement')
    core = @('test_run_skill_manager_standalone', 'test_run_skill_manager_contract', 'test_character_skill_ownership', 'test_game_system_switches', 'test_projectile_geometry', 'test_wave_schedule', 'test_spawn_queue_contract', 'test_enemy_roster_contract')
    regression = @(
        'test_run_skill_manager_standalone', 'test_run_skill_manager_contract', 'test_character_skill_ownership', 'test_game_system_switches', 'test_game_system_scene', 'test_scene_configuration_contract', 'test_world_startup',
        'test_run_skills', 'test_growth_draw', 'test_combat_buffs',
        'test_battle_only_world', 'test_ricochet_growth',
        'test_ricochet_storm', 'test_horde_simulation',
        'test_parameter_catalog', 'test_ui_live_world', 'test_projectile_geometry',
        'test_core_feedback_audio', 'test_enemy_quartet', 'test_enemy_stun',
        'test_light_pierce_attack', 'test_mirror_mark', 'test_prism_ricochet',
        'test_rooftop_pursuit', 'test_wave_health_growth', 'test_wave_hordes', 'test_wave_schedule',
        'test_spawn_queue_contract', 'test_enemy_roster_contract', 'test_combat_configuration_validation',
        'test_wave_core', 'test_wave_spawning', 'test_crowd_batch_lifecycle'
        'test_spawn_sync_gate', 'test_surround_spawning', 'test_local_spawn_safety',
        'test_run_score', 'test_score_settings', 'test_combat_extension_framework',
        'test_player_sword', 'test_crowd_deflection', 'test_native_query_policy',
        'test_enemy_update_batch', 'test_preview_query_deduplication'
    )
    render = @(
        'test_aim_target_image_cache', 'test_billboard_shadow_updates',
        'test_character_surface_normals', 'test_charge_preview_coalescing',
        'test_city_atmosphere', 'test_city_combat', 'test_combat_effect_layer',
        'test_enemy_render_reuse', 'test_player_flight_trail',
        'test_slime_ground_world', 'test_soft_foliage_shadows',
        'test_terrain_brick_grid', 'test_wet_surface_pixels'
    )
}
if ($Suite -eq 'render' -and -not $Test) {
    if ($List) { $groups.render } else {
        Write-Output 'MANUAL: screenshots, rendering and visual acceptance are performed by a person in Godot.'
        Write-Output 'World: F5; City: open scenes/city/city.tscn and press F6. No tests were executed.'
    }
    exit 0
}
if ($Test) {
    $selected = @($Test)
    foreach ($name in $selected) {
        if ($name -in $groups.render) { throw "Manual-only check: $name. Run visual acceptance in Godot; this runner only starts headless tests." }
    }
} elseif ($Suite -eq 'all') {
    $selected = @(Get-ChildItem -LiteralPath (Join-Path $projectDirectory 'tests') -Filter 'test_*.gd' | Sort-Object Name | ForEach-Object BaseName | Where-Object { $_ -notin $groups.render -and $_ -notin $groups.native })
} else {
    $selected = $groups[$Suite]
}
foreach ($name in $selected) {
    if ($name -notmatch '^test_[a-z0-9_]+$' -or -not (Test-Path -LiteralPath (Join-Path $projectDirectory "tests/$name.gd"))) {
        throw "Unknown test: $name"
    }
}
if ($List) { $selected; exit 0 }
if (-not $GodotPath) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { $GodotPath = $command.Source }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Pass -GodotPath <Godot executable> or set GODOT_BIN.'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$runDirectory = Join-Path $OutputDirectory ([DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$results = [System.Collections.Generic.List[object]]::new()
foreach ($name in $selected) {
    Write-Output "RUN $name"
    $testScript = "res://tests/$name.gd"
    if (-not $UseProjectSystemSwitches) {
        # Isolate gameplay fixtures from the user's editor switches without saving settings.
        $bootstrapPath = Join-Path $runDirectory "$name.bootstrap.gd"
        $bootstrap = @"
extends "res://tests/$name.gd"
func _initialize() -> void:
    for system in [&"upgrades", &"draft", &"run_skills"]:
        ProjectSettings.set_setting("game_manager/systems/" + String(system), true)
    super._initialize()
"@
        [System.IO.File]::WriteAllText($bootstrapPath, $bootstrap, [System.Text.UTF8Encoding]::new($false))
        $testScript = $bootstrapPath.Replace('\', '/')
    }
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $GodotPath
    $start.WorkingDirectory = $projectDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.ArgumentList.Add('--headless')
    foreach ($arg in @('--path', $projectDirectory, '--audio-driver', 'Dummy', '--script', $testScript)) {
        $start.ArgumentList.Add($arg)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
    $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    $output = $output -replace '\x1b\[[0-9;]*m', ''
    $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
    $timer.Stop()
    $process.Dispose()
    $log = Join-Path $runDirectory "$name.log"
    [System.IO.File]::WriteAllText($log, $output, [System.Text.UTF8Encoding]::new($false))
    $engineError = $output -match '(?m)^(?:SCRIPT ERROR:|ERROR:|WARNING:.*(?:leaked|still in use))'
    $passed = $exitCode -eq 0 -and -not $engineError
    $results.Add([ordered]@{ test = $name; passed = $passed; exit_code = $exitCode; engine_error = $engineError; timed_out = $timedOut; seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3); log = $log })
    Write-Output "$(if ($passed) {'PASS'} else {'FAIL'}) $name ($([Math]::Round($timer.Elapsed.TotalSeconds, 1)) s)"
    if (-not $passed) {
        $output -split "`r?`n" | Select-Object -Last 12 | Write-Output
        if ($FailFast) { break }
    }
}
$failed = @($results | Where-Object { -not $_.passed })
$summary = [ordered]@{ schema_version = 1; suite = $Suite; project = $projectDirectory; requested = $selected.Count; completed = $results.Count; passed = $results.Count - $failed.Count; failed = $failed.Count; tests = @($results.ToArray()) }
$summaryPath = Join-Path $runDirectory 'summary.json'
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Output "RESULT $($summary.passed)/$($summary.completed) passed; $summaryPath"
exit $(if ($failed.Count -eq 0) { 0 } else { 1 })
