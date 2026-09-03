[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GameRoot,
    [Parameter(Mandatory = $true)][string]$RepakPath,
    [Parameter(Mandatory = $true)][string]$UAssetGuiPath,
    [string]$PythonPath = "python.exe",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $projectRoot "scripts\common.ps1")

$layout = Resolve-GameLayout -GameRoot $GameRoot
$RepakPath = [IO.Path]::GetFullPath($RepakPath)
$UAssetGuiPath = [IO.Path]::GetFullPath($UAssetGuiPath)
$builder = Join-Path $PSScriptRoot "convert.py"
$languages = @("JA", "EN", "IT", "FR", "DE", "ES", "ZH_TW", "ZH_CN", "KR")
$expectedRepakSha256 = "FCD538E5994B9BB833622D425AE346F4E0692F02D4B0025114A559F9B6286022"
$expectedUAssetGuiSha256 = "B7D75C0893F1A60E565853AE638BC21F2416CD12C2D9D854E297ABB87CEB3263"

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $projectRoot "mod\Scripts"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

foreach ($tool in @($RepakPath, $UAssetGuiPath, $builder)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Build dependency not found: $tool"
    }
}
if ((Get-Sha256 $RepakPath) -ne $expectedRepakSha256) {
    throw "repak 0.2.3 SHA256 mismatch."
}
if ((Get-Sha256 $UAssetGuiPath) -ne $expectedUAssetGuiSha256) {
    throw "UAssetGUI 1.1.0 SHA256 mismatch."
}
$python = Get-Command $PythonPath -ErrorAction Stop | Select-Object -First 1

$tempParent = [IO.Path]::GetFullPath((Join-Path $projectRoot "temp\official-texts"))
$tempRoot = Assert-UnderDirectory (Join-Path $tempParent ([guid]::NewGuid().ToString("N"))) $tempParent
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $unpackArguments = @("unpack", "-q", "-f", "-o", $tempRoot)
    foreach ($language in $languages) {
        $assetRelative = "Octopath_Traveler2/Content/Talk/Database/TalkData_$language"
        $unpackArguments += @("-i", "$assetRelative.uasset", "-i", "$assetRelative.uexp")
    }
    $unpackArguments += $layout.Pak
    & $RepakPath @unpackArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract the official dialogue tables from the game PAK."
    }

    $outputs = [Collections.Generic.List[string]]::new()
    foreach ($language in $languages) {
        $assetRelative = "Octopath_Traveler2/Content/Talk/Database/TalkData_$language"
        $assetRoot = Join-Path $tempRoot ($assetRelative -replace "/", "\")
        $uasset = "$assetRoot.uasset"
        $uexp = "$assetRoot.uexp"
        $json = "$assetRoot.json"
        if (-not (Test-Path -LiteralPath $uasset -PathType Leaf) -or -not (Test-Path -LiteralPath $uexp -PathType Leaf)) {
            throw "TalkData_$language was not extracted from the supported game build."
        }

        & $UAssetGuiPath tojson $uasset $json VER_UE4_27 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to decode TalkData_$language."
        }
        $jsonDeadline = (Get-Date).AddSeconds(60)
        while (-not (Test-Path -LiteralPath $json -PathType Leaf) -and (Get-Date) -lt $jsonDeadline) {
            Start-Sleep -Milliseconds 250
        }
        if (-not (Test-Path -LiteralPath $json -PathType Leaf)) {
            throw "Timed out while decoding TalkData_$language."
        }

        $fileName = "official_$($language.ToLowerInvariant()).tsv"
        $output = Join-Path $tempRoot $fileName
        & $python.Source $builder --input $json --output $output --language $language
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
            throw "Failed to build $fileName."
        }
        if ((Get-Item -LiteralPath $output).Length -lt 1MB) {
            throw "$fileName is incomplete."
        }
        $outputs.Add($output)
    }

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    foreach ($output in $outputs) {
        $destination = Join-Path $OutputDirectory ([IO.Path]::GetFileName($output))
        Copy-Item -LiteralPath $output -Destination $destination -Force
        Write-Output "generated=$destination"
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
    if ((Test-Path -LiteralPath $tempParent -PathType Container) -and -not (Get-ChildItem -LiteralPath $tempParent -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $tempParent -Force
    }
}
