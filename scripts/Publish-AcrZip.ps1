[CmdletBinding()]
param(
    [string] $Version = "",

    [ValidateNotNullOrEmpty()]
    [string] $PackageSourceDirectory = "C:\Users\Administrator\AppData\Roaming\XIVLauncherCN\pluginConfigs\PromeRotation\ACRPackages\Tabris",

    [ValidateNotNullOrEmpty()]
    [string] $PackageName = "Tabris",

    [ValidateNotNullOrEmpty()]
    [string] $GitHubOwner = "Dragonw233",

    [ValidateNotNullOrEmpty()]
    [string] $GitHubRepository = "tabris-acr",

    [ValidateNotNullOrEmpty()]
    [string] $Branch = "main",

    [ValidateNotNullOrEmpty()]
    [string] $RepositoryRoot = (Get-Location).Path,

    [string] $OutputZipName = "",

    [string] $OutputJsonName = "",

    [string] $DownloadUrl = "",

    [string] $SourceRepositoryUrl = "",

    [switch] $UploadGitHubRelease,

    [switch] $ClobberGitHubRelease
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RequiredPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Kind
    )

    $resolved = @(Resolve-Path -LiteralPath $Path -ErrorAction Stop)
    if ($resolved.Count -ne 1) {
        throw "$Kind path must resolve to exactly one item: $Path"
    }

    return $resolved[0].Path
}

function Get-GitHubRepositoryName {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Owner
    )

    $remoteUrl = ""
    try {
        $remoteUrl = (& git -C $Root config --get remote.origin.url 2>$null).Trim()
    }
    catch {
        return ""
    }

    if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
        return ""
    }

    $escapedOwner = [Regex]::Escape($Owner)
    $patterns = @(
        "github\.com[:/]$escapedOwner/(?<repo>[^/\\]+?)(?:\.git)?$",
        "https://github\.com/$escapedOwner/(?<repo>[^/\\]+?)(?:\.git)?$"
    )

    foreach ($pattern in $patterns) {
        $match = [Regex]::Match($remoteUrl, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return $match.Groups["repo"].Value
        }
    }

    return ""
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Content
    )

    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

if ([string]::IsNullOrWhiteSpace($OutputZipName)) {
    $OutputZipName = "$PackageName.zip"
}

if ([string]::IsNullOrWhiteSpace($OutputJsonName)) {
    $OutputJsonName = "$PackageName.json"
}

if ([string]::IsNullOrWhiteSpace($SourceRepositoryUrl)) {
    $SourceRepositoryUrl = "https://github.com/$GitHubOwner/$GitHubRepository"
}

if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
    $DownloadUrl = "https://raw.githubusercontent.com/$GitHubOwner/$GitHubRepository/$Branch/$OutputZipName"
}

$root = Resolve-RequiredPath -Path $RepositoryRoot -Kind "Repository root"
$packageDirectory = Resolve-RequiredPath -Path $PackageSourceDirectory -Kind "Package source directory"

if (-not (Test-Path -LiteralPath $packageDirectory -PathType Container)) {
    throw "Package source path must be a directory: $packageDirectory"
}

$sourceZip = Resolve-RequiredPath -Path (Join-Path $packageDirectory "$PackageName.zip") -Kind "Source zip"
$sourceJson = Resolve-RequiredPath -Path (Join-Path $packageDirectory "$PackageName.json") -Kind "Source json"

$outputZip = Join-Path $root $OutputZipName
$outputJson = Join-Path $root $OutputJsonName

Copy-Item -LiteralPath $sourceZip -Destination $outputZip -Force

$manifest = Get-Content -Raw -LiteralPath $sourceJson | ConvertFrom-Json
if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $manifest.version = $Version
}

if ([string]::IsNullOrWhiteSpace($manifest.version)) {
    throw "Package manifest must contain a version, or pass -Version."
}

$sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputZip).Hash.ToLowerInvariant()
$manifest.downloadUrl = $DownloadUrl
$manifest.sourceRepositoryUrl = $SourceRepositoryUrl
$manifest.sha256 = $sha256

$json = ($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine
Write-Utf8NoBom -Path $outputJson -Content $json

$tagName = "v$($manifest.version)"

Write-Host "Published $PackageName $($manifest.version)"
Write-Host "Source:     $packageDirectory"
Write-Host "Zip:        $outputZip"
Write-Host "Manifest:   $outputJson"
Write-Host "SHA256:     $sha256"
Write-Host "Raw JSON:   https://raw.githubusercontent.com/$GitHubOwner/$GitHubRepository/$Branch/$OutputJsonName"

if ($UploadGitHubRelease) {
    if ([string]::IsNullOrWhiteSpace($GitHubRepository)) {
        $GitHubRepository = Get-GitHubRepositoryName -Root $root -Owner $GitHubOwner
    }

    if ([string]::IsNullOrWhiteSpace($GitHubRepository)) {
        throw "GitHub repository name is required. Pass -GitHubRepository '<repo-name>'."
    }

    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghCommand) {
        throw "GitHub CLI 'gh' was not found. Install gh or run without -UploadGitHubRelease."
    }

    $releaseTitle = "$PackageName ACR $($manifest.version)"
    $notes = @"
$PackageName ACR $($manifest.version)

Source: $PackageSourceDirectory
Manifest: https://raw.githubusercontent.com/$GitHubOwner/$GitHubRepository/$Branch/$OutputJsonName
SHA256: $sha256
"@

    $repo = "$GitHubOwner/$GitHubRepository"
    $clobberArgs = @()
    if ($ClobberGitHubRelease) {
        $clobberArgs += "--clobber"
    }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "SilentlyContinue"
        & gh release view $tagName --repo $repo *> $null
        $releaseExists = $LASTEXITCODE -eq 0
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($releaseExists) {
        & gh release edit $tagName --repo $repo --title $releaseTitle --notes $notes
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub release edit failed."
        }

        & gh release upload $tagName $outputZip $outputJson --repo $repo @clobberArgs
    }
    else {
        & gh release create $tagName $outputZip $outputJson --repo $repo --title $releaseTitle --notes $notes
    }

    if ($LASTEXITCODE -ne 0) {
        throw "GitHub release upload failed."
    }

    Write-Host "GitHub Release: https://github.com/$repo/releases/tag/$tagName"
}
