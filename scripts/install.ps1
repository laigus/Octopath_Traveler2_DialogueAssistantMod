[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GameRoot
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Assert-GameStopped
$layout = Resolve-GameLayout -GameRoot $GameRoot
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$sourceModRoot = Join-Path $projectRoot "mod"
$sourceLua = Join-Path $sourceModRoot "Scripts\main.lua"
$sourceConfig = Join-Path $sourceModRoot "Scripts\config.lua"
$sourceAnalysis = Join-Path $sourceModRoot "Scripts\analysis_ja.tsv"
$sourceSettings = Join-Path $sourceModRoot "runtime\UE4SS-settings.ini"
$sourcePak = Join-Path $sourceModRoot "pak\$script:ModPakName"
$ue4ssZip = Join-Path $sourceModRoot "runtime\UE4SS\$script:Ue4ssVersion\UE4SS_v$script:Ue4ssVersion.zip"
$translationLanguages = @("JA", "EN", "IT", "FR", "DE", "ES", "ZH_TW", "ZH_CN", "KR")
$sourceTranslations = @($translationLanguages | ForEach-Object {
    $fileName = "official_$($_.ToLowerInvariant()).tsv"
    [pscustomobject]@{
        Language = $_
        FileName = $fileName
        Path = Join-Path $sourceModRoot "Scripts\$fileName"
    }
})
$sourceLookups = @($sourceTranslations) + @([pscustomobject]@{
    FileName = "analysis_ja.tsv"
    Path = $sourceAnalysis
})

foreach ($requiredSource in @($sourceLua, $sourceConfig, $sourceSettings, $sourcePak) + @($sourceLookups.Path)) {
    if (-not (Test-Path -LiteralPath $requiredSource -PathType Leaf)) {
        throw "Install source not found: $requiredSource"
    }
}

if (Test-Path -LiteralPath $layout.Manifest -PathType Leaf) {
    $existingManifest = Get-Content -LiteralPath $layout.Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([IO.Path]::GetFullPath([string]$existingManifest.game_root) -ne $layout.Root) {
        throw "Existing install manifest belongs to another game root."
    }
    foreach ($operation in @($existingManifest.operations)) {
        if ([string]$operation.operation -in @("existing", "user_config")) { continue }
        $targetRoot = Get-OperationTargetRoot $operation
        $target = Resolve-TrackedTarget -Layout $layout -RelativePath ([string]$operation.relative_path) -TargetRoot $targetRoot
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Existing installation is incomplete; run uninstall.ps1 first: $target"
        }
        if ((Get-Sha256 $target) -ne [string]$operation.after_sha256) {
            throw "Existing installation changed; run uninstall.ps1 first: $target"
        }
    }

    $luaRelative = "Mods\$script:ModName\Scripts\main.lua"
    $luaOperation = @($existingManifest.operations | Where-Object { [string]$_.relative_path -eq $luaRelative } | Select-Object -First 1)
    if ($luaOperation.Count -ne 1) {
        throw "Installed state does not contain the Lua entry: $luaRelative"
    }
    $installedLua = Assert-UnderDirectory (Join-Path $layout.Bin $luaRelative) $layout.Bin
    $sourceLuaHash = Get-Sha256 $sourceLua
    $installState = "already_installed"
    $manifestChanged = $false
    if ([int]$existingManifest.schema_version -ne 2) {
        $existingManifest.schema_version = 2
        $manifestChanged = $true
    }
    if ($null -eq $existingManifest.PSObject.Properties["paks_dir"]) {
        $existingManifest | Add-Member -NotePropertyName paks_dir -NotePropertyValue $layout.Paks
        $manifestChanged = $true
    }
    if ((Get-Sha256 $installedLua) -ne $sourceLuaHash) {
        Copy-Item -LiteralPath $sourceLua -Destination $installedLua -Force
        $luaOperation[0].after_sha256 = $sourceLuaHash
        $installState = "updated"
        $manifestChanged = $true
    }

    $configRelative = "Mods\$script:ModName\Scripts\config.lua"
    $installedConfig = Assert-UnderDirectory (Join-Path $layout.Bin $configRelative) $layout.Bin
    $configOperation = @($existingManifest.operations | Where-Object {
        [string]$_.relative_path -eq $configRelative -and [string]$_.operation -eq "user_config"
    } | Select-Object -First 1)
    if (-not (Test-Path -LiteralPath $installedConfig -PathType Leaf)) {
        Copy-Item -LiteralPath $sourceConfig -Destination $installedConfig
        $installState = "updated"
    }
    if ($configOperation.Count -eq 0) {
        $existingManifest.operations = @($existingManifest.operations) + [pscustomobject][ordered]@{
            relative_path = $configRelative
            target_root = "bin"
            operation = "user_config"
            before_sha256 = $null
            after_sha256 = $null
            backup_relative_path = $null
        }
        $installState = "updated"
        $manifestChanged = $true
    }

    foreach ($sourceLookup in $sourceLookups) {
        $lookupRelative = "Mods\$script:ModName\Scripts\$($sourceLookup.FileName)"
        $installedLookup = Assert-UnderDirectory (Join-Path $layout.Bin $lookupRelative) $layout.Bin
        $sourceLookupHash = Get-Sha256 $sourceLookup.Path
        $lookupOperation = @($existingManifest.operations | Where-Object {
            [string]$_.relative_path -eq $lookupRelative
        } | Select-Object -First 1)
        if ($lookupOperation.Count -eq 1) {
            if ((Get-Sha256 $installedLookup) -ne $sourceLookupHash) {
                Copy-Item -LiteralPath $sourceLookup.Path -Destination $installedLookup -Force
                $lookupOperation[0].after_sha256 = $sourceLookupHash
                $installState = "updated"
                $manifestChanged = $true
            }
        } else {
            if (Test-Path -LiteralPath $installedLookup -PathType Leaf) {
                throw "Untracked runtime lookup already exists: $installedLookup"
            }
            Copy-Item -LiteralPath $sourceLookup.Path -Destination $installedLookup
            $existingManifest.operations = @($existingManifest.operations) + [pscustomobject][ordered]@{
                relative_path = $lookupRelative
                target_root = "bin"
                operation = "added"
                before_sha256 = $null
                after_sha256 = $sourceLookupHash
                backup_relative_path = $null
            }
            $installState = "updated"
            $manifestChanged = $true
        }
    }

    $pakRelative = $script:ModPakName
    $installedPak = Resolve-TrackedTarget -Layout $layout -RelativePath $pakRelative -TargetRoot "paks"
    $sourcePakHash = Get-Sha256 $sourcePak
    $pakOperation = @($existingManifest.operations | Where-Object {
        [string]$_.relative_path -eq $pakRelative -and (Get-OperationTargetRoot $_) -eq "paks"
    } | Select-Object -First 1)
    if ($pakOperation.Count -eq 1) {
        if ((Get-Sha256 $installedPak) -ne $sourcePakHash) {
            Copy-Item -LiteralPath $sourcePak -Destination $installedPak -Force
            $pakOperation[0].after_sha256 = $sourcePakHash
            $installState = "updated"
            $manifestChanged = $true
        }
    } else {
        $pakKind = "added"
        if (Test-Path -LiteralPath $installedPak -PathType Leaf) {
            if ((Get-Sha256 $installedPak) -ne $sourcePakHash) {
                throw "Untracked Mod PAK already exists with different content: $installedPak"
            }
            $pakKind = "existing"
        } else {
            Copy-Item -LiteralPath $sourcePak -Destination $installedPak
        }
        $existingManifest.operations = @($existingManifest.operations) + [pscustomobject][ordered]@{
            relative_path = $pakRelative
            target_root = "paks"
            operation = $pakKind
            before_sha256 = $null
            after_sha256 = $sourcePakHash
            backup_relative_path = $null
        }
        $installState = "updated"
        $manifestChanged = $true
    }
    if ($manifestChanged) {
        Write-Utf8NoBom -Path $layout.Manifest -Content ($existingManifest | ConvertTo-Json -Depth 8)
    }

    Write-Output "install=$installState"
    Write-Output "game_root=$($layout.Root)"
    Write-Output "manifest=$($layout.Manifest)"
    Write-Output "lua_sha256=$sourceLuaHash"
    Write-Output "translation_languages=$($translationLanguages -join ',')"
    Write-Output "pak_sha256=$sourcePakHash"
    Write-Output "config=$installedConfig"
    Write-Output "activation=next_game_launch"
    return
}

if (Test-Path -LiteralPath $layout.Target) {
    throw "A manifest-free $script:ModName directory already exists: $($layout.Target)"
}

if (-not (Test-Path -LiteralPath $ue4ssZip -PathType Leaf)) {
    throw "Bundled UE4SS archive not found: $ue4ssZip"
}
$archiveHash = Get-Sha256 $ue4ssZip
if ($archiveHash -ne $script:Ue4ssZipSha256) {
    throw "UE4SS archive SHA256 mismatch: $archiveHash"
}

$installId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$backupRoot = Assert-UnderDirectory (Join-Path $layout.Bin "$script:ModName`Backup\$installId") $layout.Bin
$tempParent = [IO.Path]::GetFullPath((Join-Path $projectRoot "temp\install"))
New-Item -ItemType Directory -Force -Path $tempParent | Out-Null
$extractDir = Assert-UnderDirectory (Join-Path $tempParent ([guid]::NewGuid().ToString("N"))) $tempParent
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
$operations = [Collections.Generic.List[object]]::new()

function Install-TrackedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$RelativeTarget,
        [ValidateSet("bin", "paks")][string]$TargetRootName = "bin",
        [switch]$RequireSameIfExisting,
        [switch]$PreserveExisting
    )

    $target = Resolve-TrackedTarget -Layout $layout -RelativePath $RelativeTarget -TargetRoot $TargetRootName
    $sourceHash = Get-Sha256 $Source
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null

    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        Copy-Item -LiteralPath $Source -Destination $target
        $operations.Add([ordered]@{
            relative_path = $RelativeTarget
            target_root = $TargetRootName
            operation = "added"
            before_sha256 = $null
            after_sha256 = $sourceHash
            backup_relative_path = $null
        })
        return
    }

    $beforeHash = Get-Sha256 $target
    if ($beforeHash -eq $sourceHash -or $PreserveExisting) {
        $operations.Add([ordered]@{
            relative_path = $RelativeTarget
            target_root = $TargetRootName
            operation = "existing"
            before_sha256 = $beforeHash
            after_sha256 = $beforeHash
            backup_relative_path = $null
        })
        return
    }
    if ($RequireSameIfExisting) {
        throw "Existing runtime file has a different SHA256: $target ($beforeHash)"
    }

    $backup = Assert-UnderDirectory (Join-Path $backupRoot $RelativeTarget) $backupRoot
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup
    Copy-Item -LiteralPath $Source -Destination $target -Force
    $operations.Add([ordered]@{
        relative_path = $RelativeTarget
        target_root = $TargetRootName
        operation = "modified"
        before_sha256 = $beforeHash
        after_sha256 = $sourceHash
        backup_relative_path = Get-RelativePathUnderDirectory $backup $layout.Bin
    })
}

function Install-UserConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$RelativeTarget
    )

    $target = Assert-UnderDirectory (Join-Path $layout.Bin $RelativeTarget) $layout.Bin
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        Copy-Item -LiteralPath $Source -Destination $target
    }
    $operations.Add([ordered]@{
        relative_path = $RelativeTarget
        target_root = "bin"
        operation = "user_config"
        before_sha256 = $null
        after_sha256 = $null
        backup_relative_path = $null
    })
}

function Undo-PartialInstall {
    $reverse = @($operations)
    [array]::Reverse($reverse)
    foreach ($operation in $reverse) {
        if ([string]$operation.operation -eq "existing") { continue }
        $targetRoot = Get-OperationTargetRoot $operation
        $target = Resolve-TrackedTarget -Layout $layout -RelativePath ([string]$operation.relative_path) -TargetRoot $targetRoot
        if ([string]$operation.operation -eq "user_config") {
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                Remove-Item -LiteralPath $target -Force
            }
            continue
        }
        if ([string]$operation.operation -eq "added") {
            if ((Test-Path -LiteralPath $target -PathType Leaf) -and (Get-Sha256 $target) -eq [string]$operation.after_sha256) {
                Remove-Item -LiteralPath $target -Force
            }
            continue
        }
        if ([string]$operation.operation -eq "modified") {
            $backup = Assert-UnderDirectory (Join-Path $layout.Bin ([string]$operation.backup_relative_path)) $layout.Bin
            if (Test-Path -LiteralPath $backup -PathType Leaf) {
                Copy-Item -LiteralPath $backup -Destination $target -Force
            }
        }
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
    if (Test-Path -LiteralPath $backupRoot -PathType Container) {
        $resolvedBackup = [IO.Path]::GetFullPath($backupRoot)
        $binPrefix = [IO.Path]::GetFullPath($layout.Bin).TrimEnd('\') + '\'
        if ($resolvedBackup.StartsWith($binPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedBackup -Recurse -Force
        }
    }
}

try {
    Expand-Archive -LiteralPath $ue4ssZip -DestinationPath $extractDir -Force
    $runtimeDll = Join-Path $extractDir "UE4SS.dll"
    $proxyDll = Join-Path $extractDir "dwmapi.dll"
    if (-not (Test-Path -LiteralPath $runtimeDll -PathType Leaf) -or -not (Test-Path -LiteralPath $proxyDll -PathType Leaf)) {
        throw "UE4SS archive layout is not recognized."
    }
    if ((Get-Sha256 $runtimeDll) -ne $script:Ue4ssDllSha256) {
        throw "UE4SS.dll SHA256 differs from the pinned runtime."
    }
    if ((Get-Sha256 $proxyDll) -ne $script:Ue4ssProxySha256) {
        throw "dwmapi.dll SHA256 differs from the pinned runtime."
    }

    $exeHashBefore = Get-Sha256 $layout.Exe
    Install-TrackedFile -Source $proxyDll -RelativeTarget "dwmapi.dll" -RequireSameIfExisting
    Install-TrackedFile -Source $runtimeDll -RelativeTarget "UE4SS.dll" -RequireSameIfExisting
    if (Test-Path -LiteralPath $layout.Settings -PathType Leaf) {
        Install-TrackedFile -Source $sourceSettings -RelativeTarget "UE4SS-settings.ini" -PreserveExisting
    } else {
        Install-TrackedFile -Source $sourceSettings -RelativeTarget "UE4SS-settings.ini"
    }
    Install-TrackedFile -Source $sourceLua -RelativeTarget "Mods\$script:ModName\Scripts\main.lua"
    foreach ($sourceLookup in $sourceLookups) {
        Install-TrackedFile -Source $sourceLookup.Path -RelativeTarget "Mods\$script:ModName\Scripts\$($sourceLookup.FileName)"
    }
    Install-UserConfig -Source $sourceConfig -RelativeTarget "Mods\$script:ModName\Scripts\config.lua"
    Install-TrackedFile -Source $sourcePak -RelativeTarget $script:ModPakName -TargetRootName "paks"

    $stagedModsTxt = Join-Path $extractDir "mods.txt"
    if (Test-Path -LiteralPath $layout.ModsTxt -PathType Leaf) {
        Copy-Item -LiteralPath $layout.ModsTxt -Destination $stagedModsTxt
    } else {
        Write-Utf8NoBom -Path $stagedModsTxt -Content ""
    }
    Set-ModEnabledLine -ModsTxt $stagedModsTxt -Enabled $true
    Install-TrackedFile -Source $stagedModsTxt -RelativeTarget "Mods\mods.txt"

    $exeHashAfter = Get-Sha256 $layout.Exe
    if ($exeHashAfter -ne $exeHashBefore) {
        throw "Game executable changed during installation."
    }

    $manifest = [ordered]@{
        schema_version = 2
        install_id = $installId
        installed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        game_root = $layout.Root
        bin_dir = $layout.Bin
        paks_dir = $layout.Paks
        backup_root_relative = Get-RelativePathUnderDirectory $backupRoot $layout.Bin
        ue4ss = [ordered]@{
            version = $script:Ue4ssVersion
            archive_sha256 = $archiveHash
        }
        protected_artifacts = @(
            [ordered]@{ relative_path = $script:ExeRelativePath; sha256 = $exeHashAfter },
            [ordered]@{ relative_path = $script:PakRelativePath; sha256 = $script:ExpectedPakSha256 }
        )
        operations = $operations
    }
    $manifestJson = $manifest | ConvertTo-Json -Depth 8
    New-Item -ItemType Directory -Force -Path $layout.Target | Out-Null
    Write-Utf8NoBom -Path $layout.Manifest -Content $manifestJson

    Write-Output "install=ok"
    Write-Output "game_root=$($layout.Root)"
    Write-Output "game_exe_sha256=$exeHashAfter"
    Write-Output "ue4ss_archive_sha256=$archiveHash"
    Write-Output "translation_languages=$($translationLanguages -join ',')"
    Write-Output "pak_sha256=$(Get-Sha256 $sourcePak)"
    Write-Output "manifest=$($layout.Manifest)"
    Write-Output "activation=next_game_launch"
} catch {
    Undo-PartialInstall
    throw
} finally {
    $resolvedExtract = [IO.Path]::GetFullPath($extractDir)
    $tempPrefix = [IO.Path]::GetFullPath($tempParent).TrimEnd('\') + '\'
    if ($resolvedExtract.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedExtract)) {
        Remove-Item -LiteralPath $resolvedExtract -Recurse -Force
    }
    if ((Test-Path -LiteralPath $tempParent -PathType Container) -and -not (Get-ChildItem -LiteralPath $tempParent -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $tempParent -Force
    }
}
