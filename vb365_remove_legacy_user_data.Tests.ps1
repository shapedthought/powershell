# Pester 5 tests for vb365_remove_legacy_user_data.ps1. Veeam cmdlets are stubbed and mocked;
# no VB365 server is needed. Generated alongside the script from the prompt at:
# https://github.com/shapedthought/awesome-veeam-prompts/tree/main/VB365-RemoveLegacyUserData
# Run: Invoke-Pester -Path ./vb365_remove_legacy_user_data.Tests.ps1 -Output Detailed

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Stubs: Pester can only mock commands that exist. Script scope, so they never shadow real cmdlets.
    function script:Get-VBORepository { [CmdletBinding()] param($Name, [switch]$LongTerm) throw 'stub called without a mock' }
    function script:Get-VBOEntityData { [CmdletBinding()] param($Repository, $Type, $Name, $User, $Organization) throw 'stub called without a mock' }
    function script:Remove-VBOEntityData {
        [CmdletBinding()]
        param($Repository, $User, [switch]$Mailbox, [switch]$ArchiveMailbox, [switch]$OneDrive, [switch]$Sites,
            [switch]$RunAsync, [switch]$WhatIf, [switch]$Confirm)
        throw 'stub called without a mock'
    }
    function script:Get-VBODataManagementSession { [CmdletBinding()] param() throw 'stub called without a mock' }

    . (Join-Path $PSScriptRoot 'vb365_remove_legacy_user_data.ps1')

    function New-BackedUpUser([string]$Upn, [string]$Display) {
        [pscustomobject]@{ DisplayName = $Display; Email = $Upn; IsMailboxBackedUp = $true; IsOneDriveBackedUp = $true }
    }
    function New-UsersCsv([string[]]$Upns) {
        $path = Join-Path $TestDrive ("users_{0}.csv" -f [guid]::NewGuid().ToString('N'))
        $lines = @('UserPrincipalName') + $Upns
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        return $path
    }
    function Get-LatestResults {
        $f = Get-ChildItem -LiteralPath $script:Out -Filter 'results_*.csv' | Sort-Object LastWriteTime | Select-Object -Last 1
        if (-not $f) { return @() }
        return @(Import-Csv -LiteralPath $f.FullName)
    }

    $script:RepoA = [pscustomobject]@{ Name = 'Legacy A'; Id = 'a' }
    $script:RepoB = [pscustomobject]@{ Name = 'Legacy B'; Id = 'b' }
    $script:RepoArchive = [pscustomobject]@{ Name = 'Azure Archive'; Id = 'arc' }
    $script:Alice = New-BackedUpUser 'alice@contoso.com' 'Alice'
    $script:Bob = New-BackedUpUser 'bob@contoso.com' 'Bob'
}

Describe 'vb365_remove_legacy_user_data' {
    BeforeEach {
        $script:Out = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Out | Out-Null

        Mock Start-Transcript { }
        Mock Stop-Transcript { }
        Mock Write-Host { }
        Mock Write-Warning { }
        Mock Read-Host { throw 'Read-Host called unexpectedly' }

        Mock Get-VBORepository -ParameterFilter { $Name -eq 'Legacy A' -and -not $LongTerm } { $script:RepoA }
        Mock Get-VBORepository -ParameterFilter { $Name -eq 'Legacy B' -and -not $LongTerm } { $script:RepoB }
        Mock Get-VBORepository -ParameterFilter { $Name -eq 'Azure Archive' -and $LongTerm } { $script:RepoArchive }
        Mock Get-VBORepository { }   # anything else: not found

        Mock Get-VBOEntityData -ParameterFilter { $Repository.Id -eq 'a' } { $script:Alice; $script:Bob }
        Mock Get-VBOEntityData -ParameterFilter { $Repository.Id -eq 'b' } { $script:Bob }
        Mock Get-VBOEntityData -ParameterFilter { $Repository.Id -eq 'arc' } { $script:Alice }

        Mock Remove-VBOEntityData { }
        Mock Get-VBODataManagementSession { }

        $script:Common = @{ OutputDirectory = $script:Out; Mailbox = $true; ArchiveMailbox = $true; OneDrive = $true; Sites = $true }
    }

    Context 'Resolving users' {
        It 'finds a user in one repository and reports NotInRepository for the other' {
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -UsersCsv $csv -RepositoryName 'Legacy A', 'Legacy B' @script:Common

            $rows = Get-LatestResults
            ($rows | Where-Object Repository -eq 'Legacy A').Status | Should -Be 'Found'
            ($rows | Where-Object Repository -eq 'Legacy A').DisplayName | Should -Be 'Alice'
            ($rows | Where-Object Repository -eq 'Legacy B').Status | Should -Be 'NotInRepository'
            $script:ExitCode | Should -Be 0
        }

        It 'matches the UPN case-insensitively' {
            $csv = New-UsersCsv @('ALICE@Contoso.com')
            Invoke-VB365LegacyUserDataRemoval -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common
            (Get-LatestResults)[0].Status | Should -Be 'Found'
        }

        It 'reports a user that is in no repository' {
            $csv = New-UsersCsv @('nobody@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -UsersCsv $csv -RepositoryName 'Legacy A', 'Legacy B' @script:Common

            $rows = Get-LatestResults
            @($rows | Where-Object Status -ne 'NotInRepository').Count | Should -Be 0
            $script:ExitCode | Should -Be 0
        }

        It 'treats two backed-up users with the same UPN as ambiguous and removes nothing' {
            $dupe = New-BackedUpUser 'bob@contoso.com' 'Bob (old)'
            Mock Get-VBOEntityData -ParameterFilter { $Repository.Id -eq 'b' } { $script:Bob; $dupe }
            $csv = New-UsersCsv @('bob@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -UsersCsv $csv -RepositoryName 'Legacy B' @script:Common

            (Get-LatestResults)[0].Status | Should -Be 'Ambiguous'
            Should -Invoke Remove-VBOEntityData -Times 0 -Exactly
            $script:ExitCode | Should -Be 1
        }

        It 'stops and lists the available properties when no email/UPN property exists' {
            Mock Get-VBOEntityData -ParameterFilter { $Repository.Id -eq 'a' } { [pscustomobject]@{ DisplayName = 'Alice'; Id = 1 } }
            $csv = New-UsersCsv @('alice@contoso.com')
            $err = $null
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common -ErrorVariable err -ErrorAction SilentlyContinue

            ($err | Out-String) | Should -Match 'No email/UPN property'
            ($err | Out-String) | Should -Match 'DisplayName, Id'
            Should -Invoke Remove-VBOEntityData -Times 0 -Exactly
            $script:ExitCode | Should -Be 2
        }

        It 'uses -MatchProperty when given' {
            Mock Get-VBOEntityData -ParameterFilter { $Repository.Id -eq 'a' } { [pscustomobject]@{ DisplayName = 'Alice'; SmtpAddr = 'alice@contoso.com' } }
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -UsersCsv $csv -RepositoryName 'Legacy A' -MatchProperty SmtpAddr @script:Common
            (Get-LatestResults)[0].Status | Should -Be 'Found'
        }

        It 'never uses the live tenant lookup' {
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common
            Should -Invoke Get-VBOEntityData -ParameterFilter { $Type -eq 'User' -and $null -eq $User }
        }
    }

    Context 'Input and argument checks' {
        It 'stops on blank and duplicate CSV rows before touching any repository' {
            # A quoted blank value: Import-Csv silently drops empty and whitespace-only lines.
            $csv = New-UsersCsv @('alice@contoso.com', '" "', ' Alice@contoso.com ')
            $err = $null
            Invoke-VB365LegacyUserDataRemoval -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common -ErrorVariable err -ErrorAction SilentlyContinue

            ($err | Out-String) | Should -Match 'blank'
            ($err | Out-String) | Should -Match 'duplicate'
            Should -Invoke Get-VBORepository -Times 0 -Exactly
            $script:ExitCode | Should -Be 2
        }

        It 'refuses to run with no workload switches' {
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -UsersCsv $csv -RepositoryName 'Legacy A' -OutputDirectory $script:Out -ErrorAction SilentlyContinue
            Should -Invoke Get-VBORepository -Times 0 -Exactly
            $script:ExitCode | Should -Be 2
        }

        It 'stops before any user is touched if a repository is not found' {
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -UsersCsv $csv -RepositoryName 'Legacy A', 'Typo Repo' @script:Common -ErrorAction SilentlyContinue
            Should -Invoke Get-VBOEntityData -Times 0 -Exactly
            Should -Invoke Remove-VBOEntityData -Times 0 -Exactly
            $script:ExitCode | Should -Be 2
        }

        It 'fetches long-term repositories with -LongTerm' {
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -UsersCsv $csv -LongTermRepositoryName 'Azure Archive' @script:Common
            Should -Invoke Get-VBORepository -ParameterFilter { $Name -eq 'Azure Archive' -and $LongTerm } -Times 1 -Exactly
            (Get-LatestResults)[0].RepositoryType | Should -Be 'LongTerm'
        }
    }

    Context 'Modes' {
        It 'Inventory makes no call to Remove-VBOEntityData' {
            $csv = New-UsersCsv @('alice@contoso.com', 'bob@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common
            Should -Invoke Remove-VBOEntityData -Times 0 -Exactly
        }

        It 'Preview calls Remove-VBOEntityData only with -WhatIf' {
            $csv = New-UsersCsv @('alice@contoso.com', 'bob@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Preview -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common
            Should -Invoke Remove-VBOEntityData -Times 2 -Exactly
            Should -Invoke Remove-VBOEntityData -ParameterFilter { -not $WhatIf } -Times 0 -Exactly
            @(Get-LatestResults | Where-Object Status -eq 'Previewed').Count | Should -Be 2
        }

        It 'Remove passes exactly one user object, the chosen workloads, -Confirm by default, and never -RunAsync' {
            Mock Get-VBOEntityData -ParameterFilter { $Repository.Id -eq 'a' } { $script:Alice; $script:Bob }
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -UsersCsv $csv -RepositoryName 'Legacy A' -OutputDirectory $script:Out -Mailbox -OneDrive

            Should -Invoke Remove-VBOEntityData -Times 1 -Exactly -ParameterFilter {
                $User -eq $script:Alice -and @($User).Count -eq 1 -and $Mailbox -and $OneDrive -and -not $ArchiveMailbox -and -not $Sites -and $Confirm -and -not $RunAsync -and -not $WhatIf
            }
        }

        It 'processes only the first resolved user with -Limit 1' {
            $csv = New-UsersCsv @('nobody@contoso.com', 'alice@contoso.com', 'bob@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -Limit 1 -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common

            Should -Invoke Remove-VBOEntityData -Times 1 -Exactly -ParameterFilter { $User -eq $script:Alice }
            (Get-LatestResults | Where-Object UserPrincipalName -eq 'bob@contoso.com').Action | Should -Be 'SkippedByLimit'
        }
    }

    Context 'Remove safeguards and resilience' {
        It 'carries on after one user fails and exits non-zero' {
            Mock Remove-VBOEntityData -ParameterFilter { $User -eq $script:Alice } { throw 'repository busy' }
            $csv = New-UsersCsv @('alice@contoso.com', 'bob@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common

            $rows = Get-LatestResults
            ($rows | Where-Object UserPrincipalName -eq 'alice@contoso.com').Status | Should -Be 'Failed'
            ($rows | Where-Object UserPrincipalName -eq 'alice@contoso.com').Detail | Should -Match 'repository busy'
            ($rows | Where-Object UserPrincipalName -eq 'bob@contoso.com').Status | Should -Match '^Removed'
            Should -Invoke Remove-VBOEntityData -Times 2 -Exactly
            $script:ExitCode | Should -Be 1
        }

        It '-Force removes nothing if the typed count is wrong' {
            Mock Read-Host { '5' }
            $csv = New-UsersCsv @('alice@contoso.com', 'bob@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -Force -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common -ErrorAction SilentlyContinue
            Should -Invoke Remove-VBOEntityData -Times 0 -Exactly
            $script:ExitCode | Should -Be 3
        }

        It '-Force with the right count suppresses the per-user prompt' {
            Mock Read-Host { '2' }
            $csv = New-UsersCsv @('alice@contoso.com', 'bob@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -Force -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common
            Should -Invoke Remove-VBOEntityData -Times 2 -Exactly -ParameterFilter { -not $Confirm -and -not $WhatIf }
        }

        It 'skips a repository that reports immutability' {
            $immutable = [pscustomobject]@{ Name = 'Legacy A'; Id = 'a'; IsImmutabilityEnabled = $true }
            Mock Get-VBORepository -ParameterFilter { $Name -eq 'Legacy A' -and -not $LongTerm } { $immutable }
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common

            Should -Invoke Remove-VBOEntityData -Times 0 -Exactly
            $row = (Get-LatestResults)[0]
            $row.Status | Should -Be 'Skipped'
            $row.Detail | Should -Match 'retention'
        }
    }

    Context 'Verification' {
        It 'marks a removed user as verified when it is no longer listed' {
            $script:Calls = 0
            Mock Get-VBOEntityData -ParameterFilter { $Repository.Id -eq 'a' } {
                $script:Calls++
                if ($script:Calls -eq 1) { $script:Alice; $script:Bob } else { $script:Bob }
            }
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common

            $row = (Get-LatestResults)[0]
            $row.Status | Should -Be 'Removed'
            $row.Detail | Should -Match 'Verified'
            $script:ExitCode | Should -Be 0
        }

        It 'flags a user still listed after removal and exits non-zero' {
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common

            (Get-LatestResults)[0].Status | Should -Be 'RemovedButStillListed'
            $script:ExitCode | Should -Be 1
        }

        It 'writes data management sessions started during the run' {
            $script:Calls = 0
            Mock Get-VBOEntityData -ParameterFilter { $Repository.Id -eq 'a' } {
                $script:Calls++
                if ($script:Calls -eq 1) { $script:Alice } else { }
            }
            Mock Get-VBODataManagementSession {
                [pscustomobject]@{ Id = 'old'; CreationTime = (Get-Date).AddDays(-1); Status = 'Success' }
                [pscustomobject]@{ Id = 'new'; CreationTime = (Get-Date).AddMinutes(1); Status = 'Success' }
            }
            $csv = New-UsersCsv @('alice@contoso.com')
            Invoke-VB365LegacyUserDataRemoval -Mode Remove -UsersCsv $csv -RepositoryName 'Legacy A' @script:Common

            $f = Get-ChildItem -LiteralPath $script:Out -Filter 'sessions_*.csv'
            $f | Should -Not -BeNullOrEmpty
            $sessions = @(Import-Csv -LiteralPath $f.FullName)
            $sessions.Count | Should -Be 1
            $sessions[0].Id | Should -Be 'new'
        }
    }
}
