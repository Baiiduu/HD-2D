#requires -Version 7.0
param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [string]$OutputDirectory,
    [string]$LogDirectory = 'D:/.codexfile/work/windows-builds',
    [string]$GodotAppData = 'D:/.codexfile/cache/godot'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (!$IsWindows) { throw 'Create the TapTap Windows package on Windows.' }
$engine = (Resolve-Path -LiteralPath $GodotPath).Path
$project = Split-Path -Parent $PSScriptRoot
$repository = Split-Path -Parent (Split-Path -Parent $project)
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repository 'dist/windows' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$build = Join-Path $OutputDirectory $stamp
$bundle = Join-Path $build 'game'
$logs = Join-Path $LogDirectory $stamp
$zip = Join-Path $build 'HD2D-windows-x64.zip'
$previousEnvironment = @{}
foreach ($key in @('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'XDG_CACHE_HOME')) {
    $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
}
try {
    # Keep editor configuration, export templates and temporary files on D:.
    $env:APPDATA = $GodotAppData
    $env:LOCALAPPDATA = $GodotAppData
    $env:XDG_CACHE_HOME = 'D:/.codexfile/cache'
    $env:TEMP = 'D:/.codexfile/tmp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Path $bundle,$logs,$env:TEMP -Force | Out-Null
    $version = (& $engine --headless --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -ne '4.7.2.stable.official.ed1daf0bf') {
        throw "Use the project's verified Godot 4.7.2 binary. Found: $version"
    }
    $template = Join-Path $GodotAppData 'Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe'
    if (!(Test-Path -LiteralPath $template)) {
        throw "Install the matching Windows export templates under: $(Split-Path -Parent $template)"
    }
    $executable = Join-Path $bundle 'HD2D.exe'
    $exportLog = Join-Path $logs 'export.log'
    & $engine --headless --path $project --export-release 'Windows Desktop' $executable *> $exportLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $exportLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)) {
        throw "Export failed. See $exportLog"
    }
    $pack = Join-Path $bundle 'HD2D.pck'
    if (!(Test-Path -LiteralPath $executable) -or !(Test-Path -LiteralPath $pack)) { throw 'Export did not produce both EXE and PCK.' }
    $checkLog = Join-Path $logs 'pack-check.log'
    $licenses = Join-Path $bundle 'licenses'
    # The exported executable reads its PCK; the checker is external and never shipped.
    & $executable --headless --script (Join-Path $PSScriptRoot 'check_windows_pack.gd') -- $licenses *> $checkLog
    if ($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $checkLog -Pattern 'WINDOWS_PACK_CHECK .*"failures":\[\]' -Quiet) -or
        (Select-String -LiteralPath $checkLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)) {
        throw "Exported-pack data check failed. See $checkLog"
    }
    $fonts = Join-Path $project 'assets/fonts'
    foreach ($source in Get-ChildItem -LiteralPath $fonts -Recurse -File -Filter '*.txt') {
        $target = Join-Path $licenses ('fonts/' + [IO.Path]::GetRelativePath($fonts, $source.FullName))
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination $target
    }
    [IO.Compression.ZipFile]::CreateFromDirectory($bundle, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
    $summary = [ordered]@{
        created_at = (Get-Date -Format o)
        engine = $version
        executable = 'HD2D.exe'
        package = $zip
        sha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        bytes = (Get-Item -LiteralPath $zip).Length
        data_check = 'passed'
        manual_playtest = 'pending'
        taptap_startup_sdk = 'not_integrated'
        logs = $logs
    }
    $summary | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $build 'build.json') -Encoding utf8
    $summary | ConvertTo-Json -Depth 3
} finally {
    foreach ($key in $previousEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $previousEnvironment[$key]) }
}
