Import-Module Pester

$scriptPath = Join-Path $PSScriptRoot '..' 'Move-StaleFiles.ps1'

Describe 'Move-StaleFiles.ps1' {
    BeforeEach {
        $script:sourceDirectory = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $script:safeDirectory = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:sourceDirectory | Out-Null
    }

    It 'does not move files during a dry run by default' {
        $filePath = Join-Path $script:sourceDirectory 'stale.txt'
        Set-Content -Path $filePath -Value 'stale content'
        [System.IO.File]::SetLastWriteTime($filePath, (Get-Date).AddYears(-2)) | Out-Null
        [System.IO.File]::SetLastAccessTime($filePath, (Get-Date).AddYears(-2)) | Out-Null

        & $scriptPath -SourceDirectory $script:sourceDirectory -SafeToDeleteDirectory $script:safeDirectory -AgeInDays 30

        Test-Path $filePath | Should -BeTrue
        Test-Path (Join-Path $script:safeDirectory 'stale.txt') | Should -BeFalse
    }

    It 'moves stale files when PerformMove is specified' {
        $filePath = Join-Path $script:sourceDirectory 'stale.txt'
        Set-Content -Path $filePath -Value 'stale content'
        [System.IO.File]::SetLastWriteTime($filePath, (Get-Date).AddYears(-2)) | Out-Null
        [System.IO.File]::SetLastAccessTime($filePath, (Get-Date).AddYears(-2)) | Out-Null

        & $scriptPath -SourceDirectory $script:sourceDirectory -SafeToDeleteDirectory $script:safeDirectory -AgeInDays 30 -PerformMove

        Test-Path $filePath | Should -BeFalse
        Test-Path (Join-Path $script:safeDirectory 'stale.txt') | Should -BeTrue
    }

    It 'creates the safe-to-delete directory when it is missing' {
        Remove-Item -LiteralPath $script:safeDirectory -Force -ErrorAction SilentlyContinue

        $filePath = Join-Path $script:sourceDirectory 'stale.txt'
        Set-Content -Path $filePath -Value 'stale content'
        [System.IO.File]::SetLastWriteTime($filePath, (Get-Date).AddYears(-2)) | Out-Null
        [System.IO.File]::SetLastAccessTime($filePath, (Get-Date).AddYears(-2)) | Out-Null

        & $scriptPath -SourceDirectory $script:sourceDirectory -SafeToDeleteDirectory $script:safeDirectory -AgeInDays 30 -PerformMove

        Test-Path $script:safeDirectory | Should -BeTrue
        Test-Path (Join-Path $script:safeDirectory 'stale.txt') | Should -BeTrue
    }

    It 'removes directories that are empty before processing' {
        $emptyDirectory = Join-Path $script:sourceDirectory 'empty'
        New-Item -ItemType Directory -Path $emptyDirectory | Out-Null

        & $scriptPath -SourceDirectory $script:sourceDirectory -SafeToDeleteDirectory $script:safeDirectory -AgeInDays 30 -PerformMove

        Test-Path $emptyDirectory | Should -BeFalse
    }

    It 'removes directories that become empty after moving stale files' {
        $nestedDirectory = Join-Path $script:sourceDirectory 'nested'
        New-Item -ItemType Directory -Path $nestedDirectory | Out-Null

        $filePath = Join-Path $nestedDirectory 'stale.txt'
        Set-Content -Path $filePath -Value 'stale content'
        [System.IO.File]::SetLastWriteTime($filePath, (Get-Date).AddYears(-2)) | Out-Null
        [System.IO.File]::SetLastAccessTime($filePath, (Get-Date).AddYears(-2)) | Out-Null

        & $scriptPath -SourceDirectory $script:sourceDirectory -SafeToDeleteDirectory $script:safeDirectory -AgeInDays 30 -PerformMove

        Test-Path $nestedDirectory | Should -BeFalse
        Test-Path (Join-Path $script:safeDirectory 'nested') | Should -BeTrue
        Test-Path (Join-Path $script:safeDirectory 'nested/stale.txt') | Should -BeTrue
    }

    It 'throws when the safe directory is inside the source directory' {
        $nestedSafe = Join-Path $script:sourceDirectory 'safe'
        { & $scriptPath -SourceDirectory $script:sourceDirectory -SafeToDeleteDirectory $nestedSafe -AgeInDays 30 -PerformMove } | Should -Throw -ErrorMessage 'The safe-to-delete directory must not be inside the source directory.'

        Test-Path $nestedSafe | Should -BeFalse
    }

    It 'allows a safe directory that shares a prefix but is not nested' {
        $safeSibling = Join-Path $TestDrive ((Split-Path -Leaf $script:sourceDirectory) + '-archive')

        $filePath = Join-Path $script:sourceDirectory 'stale.txt'
        Set-Content -Path $filePath -Value 'stale content'
        [System.IO.File]::SetLastWriteTime($filePath, (Get-Date).AddYears(-2)) | Out-Null
        [System.IO.File]::SetLastAccessTime($filePath, (Get-Date).AddYears(-2)) | Out-Null

        { & $scriptPath -SourceDirectory $script:sourceDirectory -SafeToDeleteDirectory $safeSibling -AgeInDays 30 -PerformMove } | Should -Not -Throw

        Test-Path $filePath | Should -BeFalse
        Test-Path (Join-Path $safeSibling 'stale.txt') | Should -BeTrue
    }

    It 'throws when the safe-to-delete path already exists as a file' {
        $filePath = Join-Path $script:sourceDirectory 'stale.txt'
        Set-Content -Path $filePath -Value 'stale content'
        [System.IO.File]::SetLastWriteTime($filePath, (Get-Date).AddYears(-2)) | Out-Null
        [System.IO.File]::SetLastAccessTime($filePath, (Get-Date).AddYears(-2)) | Out-Null

        $safeFile = Join-Path $TestDrive 'not-a-directory.txt'
        Set-Content -Path $safeFile -Value 'not a directory'

        { & $scriptPath -SourceDirectory $script:sourceDirectory -SafeToDeleteDirectory $safeFile -AgeInDays 30 -PerformMove } | Should -Throw -ErrorMessage 'The safe-to-delete path must be a directory.'
    }
}
