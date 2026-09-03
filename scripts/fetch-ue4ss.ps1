[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
. (Join-Path $projectRoot "scripts\common.ps1")

$destinationDirectory = Join-Path $projectRoot "mod\runtime\UE4SS\$script:Ue4ssVersion"
$destination = Join-Path $destinationDirectory "UE4SS_v$($script:Ue4ssVersion).zip"
if (Test-Path -LiteralPath $destination -PathType Leaf) {
    if ((Get-Sha256 $destination) -ne $script:Ue4ssZipSha256) {
        throw "Existing UE4SS archive SHA256 mismatch: $destination"
    }
    Write-Output "runtime=present"
    Write-Output "archive=$destination"
    return
}

$tempParent = [IO.Path]::GetFullPath((Join-Path $projectRoot "temp\runtime"))
$tempRoot = Assert-UnderDirectory (Join-Path $tempParent ([guid]::NewGuid().ToString("N"))) $tempParent
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$download = Join-Path $tempRoot "UE4SS.zip"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $script:Ue4ssUrl -OutFile $download
    if ((Get-Sha256 $download) -ne $script:Ue4ssZipSha256) {
        throw "Downloaded UE4SS archive SHA256 mismatch."
    }
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    Copy-Item -LiteralPath $download -Destination $destination
    Write-Output "runtime=downloaded"
    Write-Output "archive=$destination"
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
