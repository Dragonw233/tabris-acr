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

    [string] $RepositoryRoot = "",

    [string] $OutputZipName = "",

    [string] $OutputJsonName = "",

    [string] $DownloadUrl = "",

    [string] $SourceRepositoryUrl = "",

    [string] $GitCommitMessage = "",

    [switch] $UploadGitHubRelease,

    [switch] $ClobberGitHubRelease,

    [switch] $LocalOnly,

    [switch] $SkipGitPush,

    [switch] $NoClobberGitHubRelease
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

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

function Publish-GitRepositoryFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Branch,

        [Parameter(Mandatory = $true)]
        [string] $ZipPath,

        [Parameter(Mandatory = $true)]
        [string] $JsonPath,

        [Parameter(Mandatory = $true)]
        [string] $CommitMessage
    )

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        throw "Git was not found. Install git or run with -LocalOnly / -SkipGitPush."
    }

    $gitRoot = (& git -C $Root rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) {
        throw "Repository root is not a git checkout: $Root"
    }

    $gitRoot = (Resolve-Path -LiteralPath $gitRoot.Trim()).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
    if ($gitRoot -ne $resolvedRoot) {
        throw "RepositoryRoot must be the git top-level. Got '$resolvedRoot', git root is '$gitRoot'."
    }

    & git -C $Root add -- $ZipPath $JsonPath
    if ($LASTEXITCODE -ne 0) {
        throw "git add failed."
    }

    & git -C $Root diff --cached --quiet -- $ZipPath $JsonPath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Git:        no repository file changes to commit."
    }
    else {
        & git -C $Root commit -m $CommitMessage
        if ($LASTEXITCODE -ne 0) {
            throw "git commit failed."
        }
    }

    & git -C $Root push origin $Branch
    if ($LASTEXITCODE -ne 0) {
        throw "git push failed."
    }

    Write-Host "Git:        pushed $Branch"
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
if ([string]::IsNullOrWhiteSpace($GitCommitMessage)) {
    $GitCommitMessage = "release: sync $PackageName package $($manifest.version)"
}

Write-Host "Published $PackageName $($manifest.version)"
Write-Host "Source:     $packageDirectory"
Write-Host "Zip:        $outputZip"
Write-Host "Manifest:   $outputJson"
Write-Host "SHA256:     $sha256"
Write-Host "Raw JSON:   https://raw.githubusercontent.com/$GitHubOwner/$GitHubRepository/$Branch/$OutputJsonName"

$shouldPublishGitFiles = -not $LocalOnly -and -not $SkipGitPush
if ($shouldPublishGitFiles) {
    Publish-GitRepositoryFiles -Root $root -Branch $Branch -ZipPath $outputZip -JsonPath $outputJson -CommitMessage $GitCommitMessage
}
elseif ($LocalOnly) {
    Write-Host "Git:        skipped because -LocalOnly was specified."
}
else {
    Write-Host "Git:        skipped because -SkipGitPush was specified."
}

$shouldUploadGitHubRelease = -not $LocalOnly -or $UploadGitHubRelease

if ($shouldUploadGitHubRelease) {
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
    $shouldClobberReleaseAssets = $ClobberGitHubRelease -or -not $NoClobberGitHubRelease
    if ($shouldClobberReleaseAssets) {
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
else {
    Write-Host "GitHub Release: skipped because -LocalOnly was specified."
}
