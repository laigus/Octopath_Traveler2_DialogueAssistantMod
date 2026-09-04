[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$RepakPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
. (Join-Path $projectRoot "scripts\common.ps1")

if ($RepakPath) {
    & (Join-Path $projectRoot "scripts\build_pak\build.ps1") -RepakPath $RepakPath
} else {
    & (Join-Path $projectRoot "scripts\build_pak\build.ps1")
}
& (Join-Path $projectRoot "scripts\fetch-ue4ss.ps1")
& (Join-Path $projectRoot "scripts\installer\build.ps1")

$officialLanguages = @("ja", "en", "it", "fr", "de", "es", "zh_tw", "zh_cn", "kr")
$requiredFiles = [Collections.Generic.List[string]]::new()
$requiredFiles.Add((Join-Path $projectRoot "OctopathDialogueAssistantInstaller.exe"))
$requiredFiles.Add((Join-Path $projectRoot "README.md"))
$requiredFiles.Add((Join-Path $projectRoot "README.en.md"))
$requiredFiles.Add((Join-Path $projectRoot "scripts\common.ps1"))
$requiredFiles.Add((Join-Path $projectRoot "scripts\install.ps1"))
$requiredFiles.Add((Join-Path $projectRoot "scripts\uninstall.ps1"))
$requiredFiles.Add((Join-Path $projectRoot "mod\Scripts\main.lua"))
$requiredFiles.Add((Join-Path $projectRoot "mod\Scripts\config.lua"))
$requiredFiles.Add((Join-Path $projectRoot "mod\Scripts\analysis_ja.tsv"))
$requiredFiles.Add((Join-Path $projectRoot "mod\pak\$script:ModPakName"))
$requiredFiles.Add((Join-Path $projectRoot "mod\runtime\UE4SS-settings.ini"))
$requiredFiles.Add((Join-Path $projectRoot "mod\runtime\UE4SS\$script:Ue4ssVersion\UE4SS_v$($script:Ue4ssVersion).zip"))
foreach ($language in $officialLanguages) {
    $requiredFiles.Add((Join-Path $projectRoot "mod\Scripts\official_$language.tsv"))
}

$assetsRoot = Join-Path $projectRoot "assets"
$assetFiles = @()
if (Test-Path -LiteralPath $assetsRoot -PathType Container) {
    $assetFiles = @(Get-ChildItem -LiteralPath $assetsRoot -Recurse -File)
}
if ($assetFiles.Count -eq 0) {
    throw "README assets are missing: assets"
}
foreach ($assetFile in $assetFiles) {
    $requiredFiles.Add($assetFile.FullName)
}

$missing = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count -gt 0) {
    $relativeMissing = $missing | ForEach-Object { $_.Substring($projectRoot.Length + 1) }
    throw "Release inputs are missing:`n$($relativeMissing -join "`n")`nGenerate the TSV and PAK files as documented in docs\architecture.md."
}

if (-not $Version) {
    $git = Get-Command "git.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        $tag = ""
        $tagExitCode = 1
        $shortCommit = ""
        $shortCommitExitCode = 1
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "SilentlyContinue"
            $tag = & $git.Source -C $projectRoot describe --tags --exact-match HEAD 2>$null
            $tagExitCode = $LASTEXITCODE
            if ($tagExitCode -ne 0 -or -not $tag) {
                $shortCommit = & $git.Source -C $projectRoot rev-parse --short HEAD 2>$null
                $shortCommitExitCode = $LASTEXITCODE
            }
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($tagExitCode -eq 0 -and $tag) {
            $Version = [string]$tag
        } elseif ($shortCommitExitCode -eq 0 -and $shortCommit) {
            $Version = "$shortCommit-dev"
        }
    }
}
if (-not $Version) {
    $Version = "dev"
}
$Version = $Version.Trim()
if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') {
    throw "Version may contain only letters, numbers, dots, underscores, and hyphens."
}

$packageName = "OctopathDialogueAssistant-$Version"
$distRoot = Join-Path $projectRoot "dist"
$archivePath = Join-Path $distRoot "$packageName.zip"
$tempParent = [IO.Path]::GetFullPath((Join-Path $projectRoot "temp\release"))
$tempRoot = Assert-UnderDirectory (Join-Path $tempParent ([guid]::NewGuid().ToString("N"))) $tempParent
$stageRoot = Join-Path $tempRoot $packageName
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

function Copy-ReleaseFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRelative,
        [Parameter(Mandatory = $true)][string]$DestinationRelative
    )

    $source = Join-Path $projectRoot $SourceRelative
    $destination = Join-Path $stageRoot $DestinationRelative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}

try {
    Copy-ReleaseFile "OctopathDialogueAssistantInstaller.exe" "OctopathDialogueAssistantInstaller.exe"
    Copy-ReleaseFile "README.md" "README.md"
    Copy-ReleaseFile "README.en.md" "README.en.md"
    foreach ($assetFile in $assetFiles) {
        $assetRelative = $assetFile.FullName.Substring($projectRoot.Length + 1)
        Copy-ReleaseFile $assetRelative $assetRelative
    }
    Copy-ReleaseFile "scripts\common.ps1" "scripts\common.ps1"
    Copy-ReleaseFile "scripts\install.ps1" "scripts\install.ps1"
    Copy-ReleaseFile "scripts\uninstall.ps1" "scripts\uninstall.ps1"
    Copy-ReleaseFile "mod\Scripts\main.lua" "mod\Scripts\main.lua"
    Copy-ReleaseFile "mod\Scripts\config.lua" "mod\Scripts\config.lua"
    Copy-ReleaseFile "mod\Scripts\analysis_ja.tsv" "mod\Scripts\analysis_ja.tsv"
    foreach ($language in $officialLanguages) {
        Copy-ReleaseFile "mod\Scripts\official_$language.tsv" "mod\Scripts\official_$language.tsv"
    }
    Copy-ReleaseFile "mod\pak\$script:ModPakName" "mod\pak\$script:ModPakName"
    Copy-ReleaseFile "mod\runtime\UE4SS-settings.ini" "mod\runtime\UE4SS-settings.ini"
    Copy-ReleaseFile "mod\runtime\UE4SS\$script:Ue4ssVersion\UE4SS_v$($script:Ue4ssVersion).zip" "mod\runtime\UE4SS\$script:Ue4ssVersion\UE4SS_v$($script:Ue4ssVersion).zip"

    New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
    Compress-Archive -Path (Join-Path $stageRoot "*") -DestinationPath $archivePath -CompressionLevel Optimal -Force
    Write-Output "release=$archivePath"
    Write-Output "release_sha256=$(Get-Sha256 $archivePath)"
} finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $tempPrefix = [IO.Path]::GetFullPath($tempParent).TrimEnd('\') + '\'
    if ($resolvedTemp.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTemp)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
    if ((Test-Path -LiteralPath $tempParent -PathType Container) -and -not (Get-ChildItem -LiteralPath $tempParent -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $tempParent -Force
    }
}
