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
    native = @('test_native_swarm_kernel', 'test_native_swarm_movement', 'test_native_low_obstacles')
    core = @('test_run_skill_manager_standalone', 'test_run_skill_manager_contract', 'test_character_skill_ownership', 'test_game_system_switches', 'test_projectile_geometry', 'test_wave_schedule', 'test_spawn_queue_contract', 'test_enemy_roster_contract')
    regression = @(
        'test_control_bindings', 'test_leaderboard_state', 'test_leaderboard_auto_submit', 'test_leaderboard_ui',
        'test_controls_settings', 'test_settings_pause', 'test_character_attributes', 'test_character_panel', 'test_audio_preferences', 'test_ui_feedback', 'test_ui_audio', 'test_growth_choice_audio',
        'test_rain_toggle',
        'test_player_scene_lighting', 'test_character_spotlight',
        'test_lens_drop_tiles', 'test_lens_drop_tiles_weather', 'test_hit_debris_lifecycle', 'test_player_hurt_effect', 'test_player_hurt_screen',
        'test_wave_clear_presentation',
        'test_charge_camera_tremor', 'test_camera_edge_pan', 'test_camera_follow_limit', 'test_orbit_camera_transition',
        'test_charge_wind', 'test_charge_audio_suite', 'test_world_audio_selection', 'test_combat_sfx_integration',
        'test_hit_silhouette', 'test_hit_impact', 'test_kill_camera_balance', 'test_sword_hit_impact', 'test_hitstop_continuity', 'test_walking_sword_hitstop', 'test_damage_numbers_hitstop',
        'test_orbit_geometry_reuse', 'test_enemy_sight_reuse', 'test_range_query_work',
        'test_motion_effect_profiles', 'test_effect_shader_guards', 'test_sword_shader_work', 'test_slash_geometry_reuse', 'test_fire_spark_profiles', 'test_storm_effect_reuse',
        'test_aim_display_submission', 'test_damage_number_compaction', 'test_death_sweep_reuse',
        'test_combat_audio_balance',
        'test_kill_feedback_world', 'test_airborne_audio', 'test_wave_presentation', 'test_wave_finish_shot',
        'test_run_skill_manager_standalone', 'test_run_skill_manager_contract', 'test_character_skill_ownership', 'test_game_system_switches', 'test_game_system_scene', 'test_scene_configuration_contract', 'test_world_startup',
        'test_run_skills', 'test_growth_draw', 'test_growth_choice_ui', 'test_growth_card_copy', 'test_growth_card_presentation', 'test_skill_card_illustration', 'test_combat_buffs', 'test_critical_damage', 'test_omnivamp', 'test_epic_growth', 'test_epic_draw', 'test_epic_attacks', 'test_legendary_growth', 'test_legendary_integration', 'test_growth_pool_exhaustion', 'test_kill_haste_motion', 'test_equipment_bonus_policy',
        'test_battle_only_world', 'test_world_visual_resources', 'test_city_surroundings', 'test_battle_corner_water', 'test_ricochet_growth',
        'test_ricochet_storm', 'test_horde_simulation', 'test_orbit_movement_speed',
        'test_parameter_catalog', 'test_graphics_settings', 'test_menu_render_budget', 'test_settings_scroll', 'test_ui_live_world', 'test_main_menu', 'test_main_menu_fire', 'test_player_fire_trail', 'test_fire_flow', 'test_world_main_menu', 'test_return_to_menu', 'test_world_entry', 'test_entry_mist_lighting', 'test_building_emission_fog', 'test_building_occlusion', 'test_building_registration', 'test_static_geometry_batch', 'test_surface_storage', 'test_projectile_geometry',
        'test_body_layout_reuse', 'test_combat_prewarm', 'test_core_feedback_audio', 'test_common_hit_audio', 'test_kill_feedback_audio', 'test_death_audio_stages', 'test_charge_feedback_layers', 'test_charge_drama', 'test_charge_staging', 'test_ricochet_impact_feedback', 'test_player_surface_feedback', 'test_ricochet_impact_curve', 'test_charge_release', 'test_ricochet_speed_camera', 'test_enemy_quartet', 'test_enemy_stun', 'test_melee_death_feedback', 'test_enemy_feedback_pool', 'test_enemy_hit_reaction', 'test_orbit_presentation', 'test_orbit_slow', 'test_live_orbit_queries',
        'test_light_pierce_attack', 'test_mirror_mark', 'test_prism_ricochet', 'test_prism_enemy_bounce',
        'test_rooftop_pursuit', 'test_wave_health_growth', 'test_world_difficulty_balance', 'test_endgame_balance', 'test_wave_hordes', 'test_wave_schedule',
        'test_spawn_queue_contract', 'test_spawn_shadow_queue', 'test_spawn_shadows', 'test_enemy_roster_contract', 'test_combat_configuration_validation',
        'test_wave_core', 'test_wave_spawning', 'test_crowd_batch_lifecycle'
        'test_spawn_sync_gate', 'test_surround_spawning', 'test_local_spawn_safety',
        'test_run_score', 'test_run_score_combo', 'test_run_score_clock', 'test_score_gain_visibility', 'test_score_settings', 'test_combat_extension_framework',
        'test_world_character_animations', 'test_wall_bounce_slow', 'test_normal_sword_windup', 'test_normal_slash_alignment', 'test_player_sword', 'test_multistrike_work', 'test_flight_sword_orbit', 'test_sword_query_reuse', 'test_sword_flat_reach', 'test_sword_stretch', 'test_sword_ribbon', 'test_sword_flow', 'test_crowd_deflection', 'test_sparse_orbit_capture', 'test_native_query_policy',
        'test_enemy_update_batch', 'test_pursuit_cadence', 'test_preview_query_deduplication', 'test_ground_low_obstacles', 'test_player_ground_obstacles', 'test_pursuit_narrow_passage',
        'test_collision_surfaces', 'test_building_collision_surfaces', 'test_cyber_armillary', 'test_cyber_armillary_motion', 'test_world_audio_retirements'
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
    foreach ($arg in @('--path', $projectDirectory, '--audio-driver', 'Dummy', '--log-file', (Join-Path $runDirectory "$name.engine.log"), '--script', $testScript)) {
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
