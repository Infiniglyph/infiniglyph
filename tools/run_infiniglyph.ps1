param(
    [string]$GodotPath = (Join-Path $env:USERPROFILE 'OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe'),
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$resolvedGodot = (Resolve-Path -LiteralPath $GodotPath).Path
$resolvedProject = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $resolvedProject 'project.godot') -PathType Leaf)) {
    throw "No Godot project found at: $resolvedProject"
}

$process = Start-Process -FilePath $resolvedGodot -ArgumentList @(
    '--path', ('"{0}"' -f $resolvedProject)
) -WindowStyle Normal -PassThru -Wait
exit $process.ExitCode
