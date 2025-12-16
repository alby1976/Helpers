<#
.SYNOPSIS
Moves files that have not been accessed or modified within a specified time frame to a safe-to-delete directory.

.DESCRIPTION
The script inspects every file in the source directory (recursively) and moves those whose
LastAccessTime and LastWriteTime are both older than the age threshold. Files are moved to the
safe-to-delete directory while preserving their relative folder structure. By default, the script
performs a dry run so no files are moved unless -PerformMove is specified (or -WhatIf is overridden).
Any empty directories (apart from the source root) encountered before or after moving files are
removed to prevent leaving empty folders behind.

.PARAMETER SourceDirectory
The directory that will be scanned for stale files. Defaults to the current directory if omitted.

.PARAMETER SafeToDeleteDirectory
The destination directory that will receive stale files. Defaults to `C:\Archive\SafeToDelete` and
is created automatically when missing.

.PARAMETER AgeInDays
Number of days a file must remain unaccessed and unmodified before it is moved. Defaults to 365.

.PARAMETER PerformMove
When specified, actually moves files instead of performing the default dry run.

.EXAMPLE
PS> .\Move-StaleFiles.ps1 -SourceDirectory 'C:\Data' -SafeToDeleteDirectory 'C:\Archive\SafeToDelete' -AgeInDays 60 -PerformMove -Verbose

#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SourceDirectory = (Get-Location).ProviderPath,

    [Parameter(Position = 1)]
    [string]$SafeToDeleteDirectory = 'C:\Archive\SafeToDelete',

    [Parameter(Position = 2)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$AgeInDays = 365,

    [Parameter()]
    [switch]$PerformMove
)

$sourceFullPath = (Resolve-Path -Path $SourceDirectory).ProviderPath

if (-not $PerformMove.IsPresent -and -not $PSBoundParameters.ContainsKey('WhatIf')) {
    $WhatIfPreference = $true
}


function Get-NormalizedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return $Path.TrimEnd('\\', '/')
}

$normalizedSourceFullPath = Get-NormalizedPath -Path $sourceFullPath

$safeFullPath = [System.IO.Path]::GetFullPath($SafeToDeleteDirectory)
$normalizedSafeFullPath = Get-NormalizedPath -Path $safeFullPath
$sourceRootWithSeparator = $normalizedSourceFullPath + [System.IO.Path]::DirectorySeparatorChar

if ([string]::Equals($normalizedSafeFullPath, $normalizedSourceFullPath, [System.StringComparison]::OrdinalIgnoreCase) -or
    $normalizedSafeFullPath.StartsWith($sourceRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The safe-to-delete directory must not be inside the source directory."
}

if (Test-Path -LiteralPath $safeFullPath) {
    if (-not (Test-Path -LiteralPath $safeFullPath -PathType Container)) {
        throw "The safe-to-delete path must be a directory."
    }

    $safeFullPath = (Resolve-Path -Path $safeFullPath).ProviderPath
} else {
    Write-Verbose "Creating safe-to-delete directory: $safeFullPath"
    $safeFullPath = (New-Item -ItemType Directory -Path $safeFullPath -Force).FullName
}

$safeFullPath = Get-NormalizedPath -Path $safeFullPath

function Test-DirectoryEmpty {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return -not (Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Remove-EmptyDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath
    )

    if ($PSCmdlet.ShouldProcess($DirectoryPath, 'Remove empty directory')) {
        try {
            Remove-Item -LiteralPath $DirectoryPath -Force -ErrorAction Stop
            Write-Verbose "Removed empty directory '$DirectoryPath'"
        }
        catch {
            Write-Warning "Failed to remove directory '$DirectoryPath': $($_.Exception.Message)"
        }
    }
}

function Remove-EmptyDirectories {
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $directories = Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction Stop |
        Sort-Object FullName -Descending

    foreach ($dir in $directories) {
        if (Test-DirectoryEmpty -Path $dir.FullName) {
            Remove-EmptyDirectory -DirectoryPath $dir.FullName
        }
    }
}

function Remove-EmptyAncestors {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Root
    )

    $current = $Path
    $normalizedRoot = Get-NormalizedPath -Path $Root

    while ($current) {
        $normalizedCurrent = Get-NormalizedPath -Path $current

        if ([string]::IsNullOrWhiteSpace($normalizedCurrent)) {
            break
        }

        if ([System.String]::Equals($normalizedCurrent, $normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        if (-not $normalizedCurrent.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        if (-not (Test-Path -LiteralPath $current -PathType Container)) {
            $current = Split-Path -Path $current -Parent
            continue
        }

        if (Test-DirectoryEmpty -Path $current) {
            Remove-EmptyDirectory -DirectoryPath $current
            $current = Split-Path -Path $current -Parent
            continue
        }

        break
    }
}

$threshold = (Get-Date).AddDays(-$AgeInDays)

Remove-EmptyDirectories -Root $sourceFullPath

$files = Get-ChildItem -Path $sourceFullPath -File -Recurse -ErrorAction Stop |
    Where-Object { $_.FullName.StartsWith($safeFullPath, [System.StringComparison]::OrdinalIgnoreCase) -eq $false }

foreach ($file in $files) {
    $isStale = ($file.LastAccessTime -lt $threshold) -and ($file.LastWriteTime -lt $threshold)

    if (-not $isStale) {
        continue
    }

    $relativePath = $file.FullName.Substring($normalizedSourceFullPath.Length).TrimStart('\\', '/')
    $destinationPath = Join-Path -Path $safeFullPath -ChildPath $relativePath

    $destinationDirectory = Split-Path -Path $destinationPath -Parent
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $destinationPath")) {
        try {
            Move-Item -LiteralPath $file.FullName -Destination $destinationPath -Force -ErrorAction Stop
            Write-Verbose "Moved '$($file.FullName)' to '$destinationPath'"
            $parentDirectory = Split-Path -Path $file.FullName -Parent
            Remove-EmptyAncestors -Path $parentDirectory -Root $sourceFullPath
        }
        catch {
            Write-Warning "Failed to move '$($file.FullName)': $($_.Exception.Message)"
        }
    }
}
