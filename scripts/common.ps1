Set-StrictMode -Version Latest

$script:ModName = "OctopathDialogueAssistant"
$script:ExpectedExeSha256 = "409648E864CEEC5CA0E57A493B39D808B54BEF1E183C674F7F40CEDEDACFDBCF"
$script:ExpectedPakSha256 = "B7BC9A835A8F74BCD12034AF92C000A231DF04DCFD414AB84FF9AA5DE7F2B726"
$script:ExeRelativePath = "Octopath_Traveler2\Binaries\Win64\Octopath_Traveler2-Win64-Shipping.exe"
$script:PakRelativePath = "Octopath_Traveler2\Content\Paks\Octopath_Traveler2-WindowsNoEditor.pak"
$script:ModPakName = "OctopathDialogueAssistant_P.pak"
$script:Ue4ssVersion = "3.0.1"
$script:Ue4ssUrl = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip"
$script:Ue4ssZipSha256 = "4B47D4BCEDDD2F561A4E395BFA00924CCFC945AF576A2D0C613E6537846C57EC"
$script:Ue4ssDllSha256 = "8AC18FBFFC1EF96B0662D4A2D537B3F224C26D65CAABA7989A9404C566102B26"
$script:Ue4ssProxySha256 = "CE596412BEFA68C30B7F88F65BEB77D9BDAD55E9B96A276A5A9CF690C63F24BB"

function Assert-UnderDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $prefix = $resolvedRoot + '\'
    if (-not $resolvedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path leaves expected root: $resolvedPath"
    }
    return $resolvedPath
}

function Resolve-GameLayout {
    param([Parameter(Mandatory = $true)][string]$GameRoot)

    $root = [IO.Path]::GetFullPath($GameRoot)
    $exe = Join-Path $root $script:ExeRelativePath
    $pak = Join-Path $root $script:PakRelativePath
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw "Game executable not found: $exe"
    }
    if (-not (Test-Path -LiteralPath $pak -PathType Leaf)) {
        throw "Main PAK not found: $pak"
    }

    $exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash
    if ($exeHash -ne $script:ExpectedExeSha256) {
        throw "Unsupported game build: executable SHA256 is $exeHash"
    }

    $bin = Assert-UnderDirectory (Split-Path -Parent $exe) $root
    $paks = Assert-UnderDirectory (Split-Path -Parent $pak) $root
    $mods = Assert-UnderDirectory (Join-Path $bin "Mods") $bin
    $target = Assert-UnderDirectory (Join-Path $mods $script:ModName) $mods

    return [pscustomobject]@{
        Root = $root
        Exe = $exe
        ExeHash = $exeHash
        Pak = $pak
        Paks = $paks
        ModPak = Join-Path $paks $script:ModPakName
        Bin = $bin
        Mods = $mods
        Target = $target
        ModsTxt = Join-Path $mods "mods.txt"
        Ue4ss = Join-Path $bin "UE4SS.dll"
        Proxy = Join-Path $bin "dwmapi.dll"
        Settings = Join-Path $bin "UE4SS-settings.ini"
        Manifest = Join-Path $target "install-manifest.json"
    }
}

function Resolve-TrackedTarget {
    param(
        [Parameter(Mandatory = $true)]$Layout,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [ValidateSet("bin", "paks")][string]$TargetRoot = "bin"
    )

    if ($TargetRoot -eq "paks") {
        return Assert-UnderDirectory (Join-Path $Layout.Paks $RelativePath) $Layout.Paks
    }
    return Assert-UnderDirectory (Join-Path $Layout.Bin $RelativePath) $Layout.Bin
}

function Get-OperationTargetRoot {
    param([Parameter(Mandatory = $true)]$Operation)

    $property = $Operation.PSObject.Properties["target_root"]
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return "bin"
    }
    $value = [string]$property.Value
    if ($value -notin @("bin", "paks")) {
        throw "Unknown tracked target root: $value"
    }
    return $value
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-RelativePathUnderDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $resolvedPath = Assert-UnderDirectory $Path $Root
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $resolvedPath.Substring($resolvedRoot.Length + 1)
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Set-ModEnabledLine {
    param(
        [Parameter(Mandatory = $true)][string]$ModsTxt,
        [Parameter(Mandatory = $true)][bool]$Enabled
    )

    $content = ""
    if (Test-Path -LiteralPath $ModsTxt -PathType Leaf) {
        $loaded = Get-Content -LiteralPath $ModsTxt -Raw -Encoding UTF8
        if ($null -ne $loaded) {
            $content = $loaded
        }
    }

    $pattern = "(?im)^\s*" + [regex]::Escape($script:ModName) + "\s*:\s*[01]\s*\r?\n?"
    $content = [regex]::Replace($content, $pattern, "").TrimEnd("`r", "`n")
    if ($Enabled) {
        if ($content.Length -gt 0) {
            $content += "`r`n"
        }
        $content += "$($script:ModName) : 1"
    }
    if ($content.Length -gt 0) {
        $content += "`r`n"
    }
    Write-Utf8NoBom -Path $ModsTxt -Content $content
}

function Assert-GameStopped {
    $process = Get-Process -Name "Octopath_Traveler2-Win64-Shipping" -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        throw "Exit the game before installing or uninstalling this mod. Running PID: $($process.Id -join ',')"
    }
}
