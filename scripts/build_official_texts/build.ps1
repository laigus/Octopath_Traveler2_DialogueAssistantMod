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
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $npcHearRelative = "Octopath_Traveler2/Content/Character/Database/NPCHearData"
    $unpackArguments = @(
        "unpack", "-q", "-o", $tempRoot,
        "-i", "$npcHearRelative.uasset",
        "-i", "$npcHearRelative.uexp"
    )
    foreach ($language in $languages) {
        $talkRelative = "Octopath_Traveler2/Content/Talk/Database/TalkData_$language"
        $gameTextRelative = "Octopath_Traveler2/Content/GameText/Database/GameText$language"
        $unpackArguments += @(
            "-i", "$talkRelative.uasset",
            "-i", "$talkRelative.uexp",
            "-i", "$gameTextRelative.uasset",
            "-i", "$gameTextRelative.uexp"
        )
    }
    $unpackArguments += $layout.Pak
    & $RepakPath @unpackArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract the official text tables from the game PAK."
    }

    $npcHearRoot = Join-Path $tempRoot ($npcHearRelative -replace "/", "\")
    $npcHearUasset = "$npcHearRoot.uasset"
    $npcHearUexp = "$npcHearRoot.uexp"
    $npcHearJson = "$npcHearRoot.json"
    if (-not (Test-Path -LiteralPath $npcHearUasset -PathType Leaf) -or -not (Test-Path -LiteralPath $npcHearUexp -PathType Leaf)) {
        throw "NPCHearData was not extracted from the supported game build."
    }
    $decode = Start-Process -FilePath $UAssetGuiPath -ArgumentList @(
        "tojson", "`"$npcHearUasset`"", "`"$npcHearJson`"", "VER_UE4_27"
    ) -Wait -PassThru -WindowStyle Hidden
    if ($decode.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $npcHearJson -PathType Leaf)) {
        throw "Failed to decode NPCHearData."
    }

    $outputs = [Collections.Generic.List[string]]::new()
    foreach ($language in $languages) {
        $talkRelative = "Octopath_Traveler2/Content/Talk/Database/TalkData_$language"
        $gameTextRelative = "Octopath_Traveler2/Content/GameText/Database/GameText$language"
        $talkRoot = Join-Path $tempRoot ($talkRelative -replace "/", "\")
        $gameTextRoot = Join-Path $tempRoot ($gameTextRelative -replace "/", "\")
        $talkUasset = "$talkRoot.uasset"
        $talkUexp = "$talkRoot.uexp"
        $talkJson = "$talkRoot.json"
        $gameTextUasset = "$gameTextRoot.uasset"
        $gameTextUexp = "$gameTextRoot.uexp"
        $gameTextJson = "$gameTextRoot.json"
        if (-not (Test-Path -LiteralPath $talkUasset -PathType Leaf) -or -not (Test-Path -LiteralPath $talkUexp -PathType Leaf)) {
            throw "TalkData_$language was not extracted from the supported game build."
        }
        if (-not (Test-Path -LiteralPath $gameTextUasset -PathType Leaf) -or -not (Test-Path -LiteralPath $gameTextUexp -PathType Leaf)) {
            throw "GameText$language was not extracted from the supported game build."
        }

        $decode = Start-Process -FilePath $UAssetGuiPath -ArgumentList @(
            "tojson", "`"$talkUasset`"", "`"$talkJson`"", "VER_UE4_27"
        ) -Wait -PassThru -WindowStyle Hidden
        if ($decode.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $talkJson -PathType Leaf)) {
            throw "Failed to decode TalkData_$language."
        }
        $decode = Start-Process -FilePath $UAssetGuiPath -ArgumentList @(
            "tojson", "`"$gameTextUasset`"", "`"$gameTextJson`"", "VER_UE4_27"
        ) -Wait -PassThru -WindowStyle Hidden
        if ($decode.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $gameTextJson -PathType Leaf)) {
            throw "Failed to decode GameText$language."
        }

        $dialogueFileName = "official_$($language.ToLowerInvariant()).tsv"
        $fieldFileName = "official_field_$($language.ToLowerInvariant()).tsv"
        $dialogueOutput = Join-Path $tempRoot $dialogueFileName
        $fieldOutput = Join-Path $tempRoot $fieldFileName
        & $python.Source $builder `
            --talk-input $talkJson `
            --game-text-input $gameTextJson `
            --npc-hear-input $npcHearJson `
            --dialogue-output $dialogueOutput `
            --field-output $fieldOutput `
            --language $language
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $dialogueOutput -PathType Leaf)) {
            throw "Failed to build $dialogueFileName."
        }
        if (-not (Test-Path -LiteralPath $fieldOutput -PathType Leaf)) {
            throw "Failed to build $fieldFileName."
        }
        if ((Get-Item -LiteralPath $dialogueOutput).Length -lt 1MB) {
            throw "$dialogueFileName is incomplete."
        }
        if ((Get-Item -LiteralPath $fieldOutput).Length -lt 10KB) {
            throw "$fieldFileName is incomplete."
        }
        $outputs.Add($dialogueOutput)
        $outputs.Add($fieldOutput)
    }

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    foreach ($output in $outputs) {
        $destination = Join-Path $OutputDirectory ([IO.Path]::GetFileName($output))
        Copy-Item -LiteralPath $output -Destination $destination -Force
        Write-Output "generated=$destination"
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse
    }
    if ((Test-Path -LiteralPath $tempParent -PathType Container) -and -not (Get-ChildItem -LiteralPath $tempParent -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $tempParent
    }
}
