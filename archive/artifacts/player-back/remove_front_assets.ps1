$workspaceRoot = (Resolve-Path -LiteralPath 'D:\Project\HD-2DMap').Path.TrimEnd('\') + '\'
$taskRoot = Join-Path $workspaceRoot 'meowa-call-logs\4-制作主角基础动画'
$runtimeRoot = Join-Path $workspaceRoot 'demoWithMeowa\1\assets\meowa\player'
$discardedMedia = @()

# The user explicitly discarded every dedicated front idle/run and run-pose asset.
$frontActionRoots = @('front-run-pose', 'idle_front', 'run_front', 'run-front-v2', 'run-front-v2-clean', 'run-front-fixed', 'idle-front-fixed', 'final-front-run')
foreach ($name in $frontActionRoots) {
    $folder = Join-Path $taskRoot ('outputs\' + $name)
    if (Test-Path -LiteralPath $folder) {
        $discardedMedia += Get-ChildItem -LiteralPath $folder -Recurse -File | Where-Object { $_.Extension -in @('.png', '.webp', '.gif', '.jpg', '.jpeg') }
    }
}
if (Test-Path -LiteralPath (Join-Path $taskRoot 'final-front-run-review')) {
    $discardedMedia += Get-ChildItem -LiteralPath (Join-Path $taskRoot 'final-front-run-review') -File | Where-Object { $_.Extension -in @('.png', '.webp', '.gif') }
}
$discardedMedia += Get-ChildItem -LiteralPath $taskRoot -File | Where-Object { $_.Name -match '^(idle|run)[-_]front.*\.(png|webp|gif)$|^game-(idle|run)-front\.png$' }
foreach ($backup in (Get-ChildItem -LiteralPath $taskRoot -Directory | Where-Object { $_.Name -like 'runtime-before*' })) {
    $discardedMedia += Get-ChildItem -LiteralPath $backup.FullName -File | Where-Object { $_.Name -match '^(idle|run)_front' -or $_.Name -eq 'animations.tres' }
}
$discardedMedia += Get-ChildItem -LiteralPath $runtimeRoot -File | Where-Object { $_.Name -match '^(idle|run)_front|^front\.png($|\.)' }
$abandonedOutputRoot = Join-Path $workspaceRoot 'artifacts\player-animation\outputs'
foreach ($name in @('front-idle', 'front-run-clean')) {
    $folder = Join-Path $abandonedOutputRoot $name
    if (Test-Path -LiteralPath $folder) {
        $discardedMedia += Get-ChildItem -LiteralPath $folder -Recurse -File | Where-Object { $_.Extension -in @('.png', '.webp', '.gif', '.jpg', '.jpeg') }
    }
}
$discardedMedia = @($discardedMedia | Sort-Object FullName -Unique)
foreach ($file in $discardedMedia) {
    $resolved = (Resolve-Path -LiteralPath $file.FullName).Path
    if (-not $resolved.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a file outside the workspace"
    }
}
foreach ($file in $discardedMedia) {
    Remove-Item -LiteralPath $file.FullName
}
[pscustomobject]@{ RemovedDiscardedFrontFiles = $discardedMedia.Count; OriginalCharacterReferencePreserved = $true } | ConvertTo-Json
