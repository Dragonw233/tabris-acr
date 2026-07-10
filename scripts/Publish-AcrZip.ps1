[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $Version,

    [ValidateNotNullOrEmpty()]
    [string] $AcrSourceDirectory = "C:\Users\Administrator\AppData\Roaming\XIVLauncherCN\pluginConfigs\PromeRotation\ACR\Tabris",

    [ValidateNotNullOrEmpty()]
    [string] $PackageName = "Tabris",

    [ValidateNotNullOrEmpty()]
    [string] $Job = "BLM",

    [ValidateNotNullOrEmpty()]
    [string] $ContentScope = "Unspecified",

    [ValidateNotNullOrEmpty()]
    [string] $Author = "Dragonw233",

    [string] $Description = "PR 黑魔 ACR",

    [int] $ApiVersion = 15,

    [ValidateNotNullOrEmpty()]
    [string] $ReferencePromeVersion = "1.5.4.9",

    [ValidateNotNullOrEmpty()]
    [string] $GitHubOwner = "Dragonw233",

    [string] $GitHubRepository = "tabris-acr",

    [ValidateNotNullOrEmpty()]
    [string] $Branch = "main",

    [string] $SourceRepositoryUrl = "",

    [string] $SponsorUrl = "",

    [ValidateNotNullOrEmpty()]
    [string] $RepositoryRoot = (Get-Location).Path,

    [string] $OutputZipName = "",

    [string] $OutputJsonName = "",

    [string] $DownloadUrl = "",

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

function New-AcrPackageZip {
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourceDirectory,

        [Parameter(Mandatory = $true)]
        [string] $PackageName,

        [Parameter(Mandatory = $true)]
        [string] $DestinationZip
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path -LiteralPath $DestinationZip) {
        Remove-Item -LiteralPath $DestinationZip -Force
    }

    $files = @(Get-ChildItem -LiteralPath $SourceDirectory -Recurse -Force -File)
    if ($files.Count -eq 0) {
        throw "ACR source directory contains no files: $SourceDirectory"
    }

    $sourcePrefix = $SourceDirectory.TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
    $archive = [System.IO.Compression.ZipFile]::Open($DestinationZip, [System.IO.Compression.ZipArchiveMode]::Create)

    try {
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($sourcePrefix.Length).Replace("\", "/")
            $entryName = "$PackageName/$relativePath"
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                $file.FullName,
                $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally {
        $archive.Dispose()
    }
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

if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    Write-Warning "Version '$Version' is not in four-part form like 1.0.0.0."
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
$sourceDirectory = Resolve-RequiredPath -Path $AcrSourceDirectory -Kind "ACR source directory"

if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
    throw "ACR source path must be a directory: $sourceDirectory"
}

$outputZip = Join-Path $root $OutputZipName
New-AcrPackageZip -SourceDirectory $sourceDirectory -PackageName $PackageName -DestinationZip $outputZip

$sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputZip).Hash.ToLowerInvariant()
$outputJson = Join-Path $root $OutputJsonName
$tagName = "v$Version"

$manifest = [ordered] @{
    author = $Author
    version = $Version
    description = $Description
    supportedJobs = @(
        [ordered] @{
            job = $Job
            contentScope = $ContentScope
        }
    )
    apiVersion = $ApiVersion
    referencePromeVersion = $ReferencePromeVersion
    downloadUrl = $DownloadUrl
    sourceRepositoryUrl = $SourceRepositoryUrl
    sponsorUrl = $SponsorUrl
    sha256 = $sha256
}

$json = ($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine
Write-Utf8NoBom -Path $outputJson -Content $json

Write-Host "Published $PackageName $Version"
Write-Host "Job:        $Job"
Write-Host "Source:     $sourceDirectory"
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

    $releaseTitle = "$PackageName $Job ACR $Version"
    $notes = @"
$PackageName $Job ACR $Version

Source: $AcrSourceDirectory
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
