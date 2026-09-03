[CmdletBinding()]
param(
    [string]$RepakPath = "",
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $projectRoot "scripts\common.ps1")

$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "source"))
if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot "mod\pak\$script:ModPakName"
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

if (-not $RepakPath -and $env:REPAK_PATH) {
    $RepakPath = $env:REPAK_PATH
}
if (-not $RepakPath) {
    $repakCommand = Get-Command "repak.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($repakCommand) {
        $RepakPath = $repakCommand.Source
    }
}
if (-not $RepakPath) {
    throw "repak 0.2.3 was not found. Pass -RepakPath, set REPAK_PATH, or add repak.exe to PATH."
}
$RepakPath = [IO.Path]::GetFullPath($RepakPath)
if (-not (Test-Path -LiteralPath $RepakPath -PathType Leaf)) {
    throw "repak executable not found: $RepakPath"
}

$expectedRepakSha256 = "FCD538E5994B9BB833622D425AE346F4E0692F02D4B0025114A559F9B6286022"
if ((Get-Sha256 $RepakPath) -ne $expectedRepakSha256) {
    throw "repak 0.2.3 SHA256 mismatch."
}

$expectedEntries = @(
    "Octopath_Traveler2/Content/UserInterface/Common/Font/PC_Font/FONT_MJ_CN_WeiBei_PC.uasset",
    "Octopath_Traveler2/Content/UserInterface/Common/Font/PC_Font/FONT_MJ_CN_WeiBei_PC.uexp",
    "Octopath_Traveler2/Content/UserInterface/Option/BP/OptionMenuWBP.uasset",
    "Octopath_Traveler2/Content/UserInterface/Option/BP/OptionMenuWBP.uexp"
)

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "PAK source directory not found: $sourceRoot"
}
$actualEntries = @(
    Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | ForEach-Object {
        $_.FullName.Substring($sourceRoot.Length + 1).Replace("\", "/")
    } | Sort-Object
)
$expectedSorted = @($expectedEntries | Sort-Object)
if (($actualEntries -join "`n") -ne ($expectedSorted -join "`n")) {
    throw "scripts\build_pak\source must contain exactly the four documented override files."
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$tempParent = [IO.Path]::GetFullPath((Join-Path $projectRoot "temp\build-pak"))
$tempRoot = Assert-UnderDirectory (Join-Path $tempParent ([guid]::NewGuid().ToString("N"))) $tempParent
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$stagedPak = Join-Path $tempRoot $script:ModPakName

try {
    & $RepakPath pack --version V11 --compression Zlib `
        --mount-point ../../../ --path-hash-seed 836401085 `
        $sourceRoot $stagedPak
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stagedPak -PathType Leaf)) {
        throw "Failed to build the Mod PAK."
    }

    $packedEntries = @(& $RepakPath list $stagedPak | Where-Object { $_ } | Sort-Object)
    if ($LASTEXITCODE -ne 0 -or ($packedEntries -join "`n") -ne ($expectedSorted -join "`n")) {
        throw "The generated PAK does not contain the expected four files."
    }

    Copy-Item -LiteralPath $stagedPak -Destination $OutputPath -Force
    Write-Output "built=$OutputPath"
    Write-Output "pak_sha256=$(Get-Sha256 $OutputPath)"
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
