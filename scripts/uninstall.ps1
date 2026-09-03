[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GameRoot,
    [string]$ManifestPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Assert-GameStopped
$layout = Resolve-GameLayout -GameRoot $GameRoot
if (-not $ManifestPath) {
    $ManifestPath = $layout.Manifest
}
$ManifestPath = [IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Install state not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([IO.Path]::GetFullPath([string]$manifest.game_root) -ne $layout.Root) {
    throw "Install state game root does not match the requested game root."
}
if ([IO.Path]::GetFullPath([string]$manifest.bin_dir) -ne $layout.Bin) {
    throw "Install state Win64 directory does not match the resolved game layout."
}

$operations = @($manifest.operations)
[array]::Reverse($operations)
foreach ($operation in $operations) {
    $targetRoot = Get-OperationTargetRoot $operation
    $target = Resolve-TrackedTarget -Layout $layout -RelativePath ([string]$operation.relative_path) -TargetRoot $targetRoot
    $kind = [string]$operation.operation
    if ($kind -eq "user_config") {
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
            Write-Output "removed=$target"
        }
        continue
    }
    if ($kind -eq "existing") {
        Write-Output "kept=$target"
        continue
    }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "Installed file is missing: $target"
    }
    if ((Get-Sha256 $target) -ne [string]$operation.after_sha256) {
        throw "Installed file changed after installation: $target"
    }

    if ($kind -eq "added") {
        Remove-Item -LiteralPath $target -Force
        Write-Output "removed=$target"
        continue
    }
    if ($kind -eq "modified") {
        $backup = Assert-UnderDirectory (Join-Path $layout.Bin ([string]$operation.backup_relative_path)) $layout.Bin
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            throw "Backup is missing: $backup"
        }
        if ((Get-Sha256 $backup) -ne [string]$operation.before_sha256) {
            throw "Backup SHA256 mismatch: $backup"
        }
        Copy-Item -LiteralPath $backup -Destination $target -Force
        if ((Get-Sha256 $target) -ne [string]$operation.before_sha256) {
            throw "Restored file SHA256 mismatch: $target"
        }
        Write-Output "restored=$target"
        continue
    }
    throw "Unknown install operation: $kind"
}

if (Test-Path -LiteralPath $layout.Manifest -PathType Leaf) {
    Remove-Item -LiteralPath $layout.Manifest -Force
}

foreach ($relativeDirectory in @(
    "Mods\$script:ModName\Scripts",
    "Mods\$script:ModName",
    "Mods"
)) {
    $directory = Assert-UnderDirectory (Join-Path $layout.Bin $relativeDirectory) $layout.Bin
    if ((Test-Path -LiteralPath $directory -PathType Container) -and -not (Get-ChildItem -LiteralPath $directory -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $directory -Force
    }
}

$backupRoot = Assert-UnderDirectory (Join-Path $layout.Bin ([string]$manifest.backup_root_relative)) $layout.Bin
if (Test-Path -LiteralPath $backupRoot -PathType Container) {
    $resolvedBackup = [IO.Path]::GetFullPath($backupRoot)
    $binPrefix = [IO.Path]::GetFullPath($layout.Bin).TrimEnd('\') + '\'
    if (-not $resolvedBackup.StartsWith($binPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup cleanup path leaves Win64: $resolvedBackup"
    }
    Remove-Item -LiteralPath $resolvedBackup -Recurse -Force
    $backupParent = Split-Path -Parent $resolvedBackup
    if ((Test-Path -LiteralPath $backupParent -PathType Container) -and -not (Get-ChildItem -LiteralPath $backupParent -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $backupParent -Force
    }
}

Write-Output "uninstall=ok"
Write-Output "game_root=$($layout.Root)"
Write-Output "game_exe_sha256=$($layout.ExeHash)"
