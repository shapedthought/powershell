<#
.SYNOPSIS
    Removes backed-up user data from legacy Veeam Backup for Microsoft 365 repositories for a list of UPNs.

.DESCRIPTION
    Generated from the VB365-RemoveLegacyUserData prompt in
    https://github.com/shapedthought/awesome-veeam-prompts. The prompt and its cmdlet contract are the
    source of truth; feed any behaviour change back into the prompt.

    Intended for clean-up after users have moved to Veeam Data Cloud. Uses the supported
    Remove-VBOEntityData cmdlet only. It never touches the object storage directly and never changes jobs.

    The script fails safe:
      * Inventory (the default) is read-only.
      * Preview runs Remove-VBOEntityData with -WhatIf.
      * Remove deletes data. It prompts per user unless -Force is given, and -Force first requires the
        operator to type the exact number of users that will be removed.

    Users are matched on UPN against the BACKED-UP data (Get-VBOEntityData -Type User), not the live
    tenant, so users already deleted from Entra ID are still found. A UPN that matches more than one
    backed-up user is an error for that user and that repository, never a guess.

    Property names on the Veeam objects are not documented. The script discovers them with Get-Member and
    stops if it cannot find a single clear email/UPN property. Use -MatchProperty to name it explicitly.

    Run on the VB365 server. Requires the Veeam.Archiver.PowerShell module.
    Works in Windows PowerShell 5.1 and PowerShell 7.

.PARAMETER Mode
    Inventory (default, read-only), Preview (Remove-VBOEntityData -WhatIf) or Remove (deletes data).

.PARAMETER UsersCsv
    CSV file with a UserPrincipalName column. Blank and duplicate rows stop the run before anything else.

.PARAMETER RepositoryName
    One or more primary (backup job) repository names.

.PARAMETER LongTermRepositoryName
    Zero or more backup copy / archive repository names, fetched with Get-VBORepository -LongTerm.

.PARAMETER Mailbox
    Remove mailbox data.

.PARAMETER ArchiveMailbox
    Remove archive mailbox data.

.PARAMETER OneDrive
    Remove OneDrive data.

.PARAMETER Sites
    Remove the user's sites data. Group and Team data are out of scope.

.PARAMETER MatchProperty
    Name of the email/UPN property on the backed-up user object. Only needed if auto-detection stops.

.PARAMETER Force
    Remove mode only. Suppresses the per-user confirmation prompt after the operator types the exact
    number of users to be removed.

.PARAMETER Limit
    Process only the first N resolved users (CSV order). Use -Limit 1 for a canary run.

.PARAMETER OutputDirectory
    Folder for the results CSV, the sessions CSV and the transcript. Defaults to the current folder.

.EXAMPLE
    .\vb365_remove_legacy_user_data.ps1 -UsersCsv .\users.csv -RepositoryName "Legacy Repository" -Mailbox -ArchiveMailbox -OneDrive -Sites

    Inventory run (read-only). Writes results_<timestamp>.csv showing which users were found where.

.EXAMPLE
    .\vb365_remove_legacy_user_data.ps1 -Mode Preview -UsersCsv .\users.csv -RepositoryName "Legacy Repository" -LongTermRepositoryName "Azure Archive" -Mailbox -ArchiveMailbox -OneDrive -Sites

    Preview run. Calls Remove-VBOEntityData with -WhatIf; nothing is deleted.

.EXAMPLE
    .\vb365_remove_legacy_user_data.ps1 -Mode Remove -Limit 1 -UsersCsv .\canary.csv -RepositoryName "Legacy Repository" -Mailbox -ArchiveMailbox -OneDrive -Sites

    Canary removal for one non-critical user, with a confirmation prompt. Check the user in Veeam
    Explorer afterwards before going further.

.EXAMPLE
    .\vb365_remove_legacy_user_data.ps1 -Mode Remove -Force -UsersCsv .\users.csv -RepositoryName "Legacy Repository" -LongTermRepositoryName "Azure Archive" -Mailbox -ArchiveMailbox -OneDrive -Sites

    Full removal. Asks you to type the number of users before it starts, then runs without per-user prompts.

.NOTES
    Removal is irreversible. Disable the legacy jobs, or take these users out of their scope, first,
    or the next run backs the data up again. Immutable repositories are skipped: their data has to age
    out through retention. This script has no association with Veeam.
#>
[CmdletBinding()]
param(
    [ValidateSet('Inventory', 'Preview', 'Remove')]
    [string]$Mode = 'Inventory',
    [string]$UsersCsv,
    [string[]]$RepositoryName = @(),
    [string[]]$LongTermRepositoryName = @(),
    [switch]$Mailbox,
    [switch]$ArchiveMailbox,
    [switch]$OneDrive,
    [switch]$Sites,
    [string]$MatchProperty,
    [switch]$Force,
    [int]$Limit = 0,
    [string]$OutputDirectory = '.'
)

Set-StrictMode -Version 2.0
$script:ExitCode = 0

#region Helpers

# Candidate names for the email/UPN property on a backed-up user object (UNVERIFIED in the docs).
$script:EmailPropertyCandidates = @('Email', 'EmailAddress', 'Mail', 'UserPrincipalName', 'UPN', 'PrimarySmtpAddress', 'UserName')

function Get-PropertyNames {
    param($InputObject)
    if ($null -eq $InputObject) { return @() }
    return @($InputObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name)
}

function Import-UserList {
    <# Returns the UPN list, or throws listing every blank or duplicate row. #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Users CSV not found: $Path" }
    $rows = @(Import-Csv -LiteralPath $Path)
    if ($rows.Count -eq 0) { throw "Users CSV is empty: $Path" }
    if ((Get-PropertyNames $rows[0]) -notcontains 'UserPrincipalName') {
        throw "Users CSV has no UserPrincipalName column: $Path"
    }

    $problems = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $upns = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $line = $i + 2   # header is line 1
        $value = [string]$rows[$i].UserPrincipalName
        $value = $value.Trim()
        if ([string]::IsNullOrWhiteSpace($value)) { $problems.Add("line ${line}: blank UserPrincipalName"); continue }
        $key = $value.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { $problems.Add("line ${line}: duplicate of line $($seen[$key]) ($value)"); continue }
        $seen[$key] = $line
        $upns.Add($value)
    }
    if ($problems.Count -gt 0) {
        throw ("Users CSV has {0} problem row(s). Fix the file and run again:`n  {1}" -f $problems.Count, ($problems -join "`n  "))
    }
    return , $upns.ToArray()
}

function Resolve-Repositories {
    <# Resolves every repository name to exactly one object, or throws before any user is touched. #>
    param([string[]]$Primary = @(), [string[]]$LongTerm = @())

    $resolved = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    $specs = @()
    foreach ($n in $Primary) { $specs += , @($n, 'Primary') }
    foreach ($n in $LongTerm) { $specs += , @($n, 'LongTerm') }

    foreach ($spec in $specs) {
        $name = $spec[0]; $type = $spec[1]
        try {
            if ($type -eq 'LongTerm') { $found = @(Get-VBORepository -Name $name -LongTerm) }
            else { $found = @(Get-VBORepository -Name $name) }
        }
        catch { $errors.Add("$type repository '$name': $($_.Exception.Message)"); continue }
        $found = @($found | Where-Object { $null -ne $_ })
        if ($found.Count -eq 0) { $errors.Add("$type repository '$name' not found") }
        elseif ($found.Count -gt 1) { $errors.Add("$type repository '$name' matched $($found.Count) repositories") }
        else { $resolved.Add([pscustomobject]@{ Name = $name; Type = $type; Repository = $found[0] }) }
    }
    if ($errors.Count -gt 0) { throw ("Repository check failed:`n  " + ($errors -join "`n  ")) }
    return , $resolved.ToArray()
}

function Find-MatchProperty {
    <# Picks the email/UPN property on a backed-up user object, or throws listing what is available. #>
    param([Parameter(Mandatory)]$SampleObject, [string]$Override)

    $names = Get-PropertyNames $SampleObject
    if ($Override) {
        if ($names -contains $Override) { return ($names | Where-Object { $_ -eq $Override } | Select-Object -First 1) }
        throw ("-MatchProperty '{0}' does not exist on the backed-up user object. Available properties: {1}" -f $Override, ($names -join ', '))
    }
    $hits = @($names | Where-Object { $script:EmailPropertyCandidates -contains $_ })
    # Prefer an explicit email/UPN over a generic UserName when both exist.
    if ($hits.Count -gt 1) {
        $preferred = @($hits | Where-Object { $_ -ne 'UserName' })
        if ($preferred.Count -eq 1) { $hits = $preferred }
    }
    if ($hits.Count -eq 1) { return $hits[0] }
    $why = if ($hits.Count -eq 0) { 'No email/UPN property found' } else { "More than one candidate ($($hits -join ', '))" }
    throw ("{0} on the backed-up user object. Re-run with -MatchProperty <name>. Available properties: {1}" -f $why, ($names -join ', '))
}

function Get-DisplayNameValue {
    param($InputObject)
    $names = Get-PropertyNames $InputObject
    foreach ($candidate in @('DisplayName', 'Name')) {
        if ($names -contains $candidate) { return [string]$InputObject.$candidate }
    }
    return ''
}

function Get-WorkloadFlags {
    <# Summarises boolean properties that look like per-workload flags. Blank if none exist. #>
    param($InputObject)
    if ($null -eq $InputObject) { return '' }
    $parts = @()
    foreach ($p in $InputObject.PSObject.Properties) {
        if ($p.Name -match 'Mailbox|Archive|OneDrive|Site' -and $p.Value -is [bool]) { $parts += ('{0}={1}' -f $p.Name, $p.Value) }
    }
    return ($parts -join ';')
}

function Get-RepositoryImmutability {
    <# $true / $false if the repository exposes an immutability flag, $null if it cannot be determined. #>
    param($Repository)
    foreach ($p in $Repository.PSObject.Properties) {
        if ($p.Name -match 'Immutab' -and $p.Value -is [bool]) { return [bool]$p.Value }
    }
    return $null
}

function Get-BackedUpUsers {
    param($Repository)
    return , @(Get-VBOEntityData -Repository $Repository -Type User | Where-Object { $null -ne $_ })
}

function Find-UserMatch {
    <# Exact, case-insensitive match on the chosen property. Returns Status Found / NotInRepository / Ambiguous. #>
    param([string]$Upn, [object[]]$Entities, [string]$Property)
    $matched = @($Entities | Where-Object { [string]::Equals([string]$_.$Property, $Upn, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($matched.Count -eq 1) { return [pscustomobject]@{ Status = 'Found'; Entity = $matched[0]; Count = 1 } }
    if ($matched.Count -eq 0) { return [pscustomobject]@{ Status = 'NotInRepository'; Entity = $null; Count = 0 } }
    return [pscustomobject]@{ Status = 'Ambiguous'; Entity = $null; Count = $matched.Count }
}

function New-ResultRow {
    param($Upn, $Repo, $Status, $Action, $Entity, $Detail)
    [pscustomobject][ordered]@{
        Timestamp         = (Get-Date).ToString('s')
        UserPrincipalName = $Upn
        Repository        = $Repo.Name
        RepositoryType    = $Repo.Type
        Mode              = $script:RunMode
        Status            = $Status
        Action            = $Action
        DisplayName       = (Get-DisplayNameValue $Entity)
        WorkloadFlags     = (Get-WorkloadFlags $Entity)
        Detail            = $Detail
    }
}

function Get-RunSessions {
    <# Data management sessions started at or after $Since, using whatever datetime property exists. #>
    param([datetime]$Since)
    $all = @(Get-VBODataManagementSession | Where-Object { $null -ne $_ })
    if ($all.Count -eq 0) { return , @() }
    $timeProp = $null
    foreach ($candidate in @('CreationTime', 'StartTime', 'Started', 'StartedAt', 'CreatedAt')) {
        if ((Get-PropertyNames $all[0]) -contains $candidate) { $timeProp = $candidate; break }
    }
    if (-not $timeProp) {
        Write-Warning ("Get-VBODataManagementSession has no start-time property this script recognises. Available properties: {0}. Check the sessions in the VB365 console." -f ((Get-PropertyNames $all[0]) -join ', '))
        return , @()
    }
    return , @($all | Where-Object { $_.$timeProp -is [datetime] -and $_.$timeProp -ge $Since })
}

#endregion

#region Main

function Invoke-VB365LegacyUserDataRemoval {
    [CmdletBinding()]
    param(
        [ValidateSet('Inventory', 'Preview', 'Remove')][string]$Mode = 'Inventory',
        [string]$UsersCsv,
        [string[]]$RepositoryName = @(),
        [string[]]$LongTermRepositoryName = @(),
        [switch]$Mailbox, [switch]$ArchiveMailbox, [switch]$OneDrive, [switch]$Sites,
        [string]$MatchProperty,
        [switch]$Force,
        [int]$Limit = 0,
        [string]$OutputDirectory = '.'
    )

    $script:ExitCode = 0
    $script:RunMode = $Mode
    $runStart = Get-Date
    $stamp = $runStart.ToString('yyyyMMdd_HHmmss')

    # ---- Argument checks (nothing touched yet) -------------------------------------------------------
    if (-not $UsersCsv) { Write-Error '-UsersCsv is required.'; $script:ExitCode = 2; return }
    if (@($RepositoryName).Count + @($LongTermRepositoryName).Count -eq 0) {
        Write-Error 'Give at least one -RepositoryName or -LongTermRepositoryName.'; $script:ExitCode = 2; return
    }
    if (-not ($Mailbox -or $ArchiveMailbox -or $OneDrive -or $Sites)) {
        Write-Error 'Choose at least one of -Mailbox, -ArchiveMailbox, -OneDrive, -Sites. There is no "all" default.'; $script:ExitCode = 2; return
    }
    if ($Force -and $Mode -ne 'Remove') { Write-Warning '-Force only applies to -Mode Remove and is ignored.' }
    if ($Limit -lt 0) { Write-Error '-Limit must be 0 (no limit) or more.'; $script:ExitCode = 2; return }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }
    $resultsPath = Join-Path $OutputDirectory "results_$stamp.csv"
    $sessionsPath = Join-Path $OutputDirectory "sessions_$stamp.csv"
    $transcriptPath = Join-Path $OutputDirectory "transcript_$stamp.txt"

    $results = New-Object System.Collections.Generic.List[object]
    $transcriptStarted = $false
    try {
        try { Start-Transcript -Path $transcriptPath | Out-Null; $transcriptStarted = $true }
        catch { Write-Warning "Could not start transcript: $($_.Exception.Message)" }

        Write-Host "Mode: $Mode" -ForegroundColor Cyan
        if ($Mode -eq 'Remove') { Write-Host 'REMOVE MODE: data removed by this run cannot be recovered.' -ForegroundColor Red }

        # ---- Users and repositories ------------------------------------------------------------------
        try { $upns = Import-UserList -Path $UsersCsv }
        catch { Write-Error $_.Exception.Message; $script:ExitCode = 2; return }
        Write-Host ("{0} user(s) in {1}" -f $upns.Count, $UsersCsv)

        try { $repos = Resolve-Repositories -Primary $RepositoryName -LongTerm $LongTermRepositoryName }
        catch { Write-Error $_.Exception.Message; $script:ExitCode = 2; return }

        # ---- Pre-flight for anything that calls Remove-VBOEntityData ---------------------------------
        if ($Mode -ne 'Inventory') {
            Write-Warning 'Legacy jobs that point at these repositories must be disabled, or must no longer include these users. Otherwise the next run backs the data up again. This script does not change jobs.'
        }
        $skipRepo = @{}
        foreach ($r in $repos) {
            $immutable = Get-RepositoryImmutability $r.Repository
            if ($immutable -eq $true) {
                $skipRepo[$r.Name + '|' + $r.Type] = 'Repository has data immutability enabled. Data must age out through retention; Remove-VBOEntityData cannot remove it.'
                Write-Warning "$($r.Type) repository '$($r.Name)' has immutability enabled and will be skipped."
            }
            elseif ($null -eq $immutable -and $Mode -ne 'Inventory') {
                Write-Warning "Could not tell whether $($r.Type) repository '$($r.Name)' is immutable. Carrying on; Remove-VBOEntityData refuses immutable repositories."
            }
        }

        # ---- Index backed-up users per repository ----------------------------------------------------
        $index = @{}
        $matchProp = $null
        foreach ($r in $repos) {
            $key = $r.Name + '|' + $r.Type
            $entities = Get-BackedUpUsers -Repository $r.Repository
            $index[$key] = $entities
            if (-not $matchProp -and $entities.Count -gt 0) {
                try { $matchProp = Find-MatchProperty -SampleObject $entities[0] -Override $MatchProperty }
                catch { Write-Error $_.Exception.Message; $script:ExitCode = 2; return }
                Write-Host "Matching users on property '$matchProp'"
            }
            Write-Host ("{0} repository '{1}': {2} backed-up user(s)" -f $r.Type, $r.Name, $entities.Count)
        }

        # ---- Resolve every user in every repository --------------------------------------------------
        $plan = New-Object System.Collections.Generic.List[object]   # one entry per user
        foreach ($upn in $upns) {
            $perRepo = @()
            foreach ($r in $repos) {
                $key = $r.Name + '|' + $r.Type
                if (-not $matchProp) { $m = [pscustomobject]@{ Status = 'NotInRepository'; Entity = $null; Count = 0 } }
                else { $m = Find-UserMatch -Upn $upn -Entities $index[$key] -Property $matchProp }
                $perRepo += [pscustomobject]@{ Repo = $r; Match = $m }
            }
            $plan.Add([pscustomobject]@{
                    Upn      = $upn
                    PerRepo  = $perRepo
                    Resolved = (@($perRepo | Where-Object { $_.Match.Status -eq 'Found' }).Count -gt 0)
                })
        }

        $selected = @($plan | Where-Object { $_.Resolved })
        if ($Limit -gt 0 -and $selected.Count -gt $Limit) {
            Write-Host ("-Limit {0}: processing the first {0} of {1} resolved user(s)" -f $Limit, $selected.Count) -ForegroundColor Yellow
            $selected = @($selected | Select-Object -First $Limit)
        }
        $selectedUpns = @{}
        foreach ($s in $selected) { $selectedUpns[$s.Upn.ToLowerInvariant()] = $true }

        # ---- -Force needs the operator to type the count ----------------------------------------------
        $suppressPrompt = $false
        if ($Mode -eq 'Remove' -and $Force) {
            $expected = $selected.Count
            $typed = Read-Host ("-Force: type the number of users that will be removed ({0} resolved) to continue" -f $expected)
            if ([string]$typed -ne [string]$expected) {
                Write-Error ("Typed '{0}', expected '{1}'. Nothing was removed." -f $typed, $expected)
                $script:ExitCode = 3
                return
            }
            $suppressPrompt = $true
        }

        # ---- Act --------------------------------------------------------------------------------------
        $workloadArgs = @{}
        if ($Mailbox) { $workloadArgs['Mailbox'] = $true }
        if ($ArchiveMailbox) { $workloadArgs['ArchiveMailbox'] = $true }
        if ($OneDrive) { $workloadArgs['OneDrive'] = $true }
        if ($Sites) { $workloadArgs['Sites'] = $true }
        $workloadText = ($workloadArgs.Keys | Sort-Object) -join ','

        foreach ($entry in $plan) {
            $inScope = $selectedUpns.ContainsKey($entry.Upn.ToLowerInvariant())
            foreach ($pr in $entry.PerRepo) {
                $r = $pr.Repo; $m = $pr.Match; $key = $r.Name + '|' + $r.Type
                # if/continue, not switch: inside a switch, continue applies to the switch, not this loop.
                if ($m.Status -eq 'NotInRepository') {
                    $results.Add((New-ResultRow $entry.Upn $r 'NotInRepository' 'None' $null 'No backed-up user with this UPN in this repository'))
                    continue
                }
                if ($m.Status -eq 'Ambiguous') {
                    $results.Add((New-ResultRow $entry.Upn $r 'Ambiguous' 'None' $null ("{0} backed-up users match this UPN. Nothing removed; investigate in the VB365 console." -f $m.Count)))
                    continue
                }
                # Found
                if ($Mode -eq 'Inventory') { $results.Add((New-ResultRow $entry.Upn $r 'Found' 'None' $m.Entity '')); continue }
                if (-not $inScope) { $results.Add((New-ResultRow $entry.Upn $r 'Found' 'SkippedByLimit' $m.Entity "Outside -Limit $Limit")); continue }
                if ($skipRepo.ContainsKey($key)) { $results.Add((New-ResultRow $entry.Upn $r 'Skipped' 'None' $m.Entity $skipRepo[$key])); continue }

                # Defence in depth: never hand an array to -User.
                if (@($m.Entity).Count -ne 1) { $results.Add((New-ResultRow $entry.Upn $r 'Ambiguous' 'None' $null 'Internal check: match was not a single object')); continue }

                $removeArgs = @{ Repository = $r.Repository; User = $m.Entity }
                foreach ($k in $workloadArgs.Keys) { $removeArgs[$k] = $true }
                if ($Mode -eq 'Preview') { $removeArgs['WhatIf'] = $true }
                else { $removeArgs['Confirm'] = (-not $suppressPrompt) }

                try {
                    Write-Host ("{0} {1} in {2} repository '{3}' ({4})" -f $(if ($Mode -eq 'Preview') { 'Previewing removal for' } else { 'Removing' }), $entry.Upn, $r.Type, $r.Name, $workloadText)
                    Remove-VBOEntityData @removeArgs -ErrorAction Stop
                    $status = if ($Mode -eq 'Preview') { 'Previewed' } else { 'Removed' }
                    $results.Add((New-ResultRow $entry.Upn $r $status $workloadText $m.Entity ''))
                }
                catch {
                    $results.Add((New-ResultRow $entry.Upn $r 'Failed' $workloadText $m.Entity $_.Exception.Message))
                    Write-Warning ("Failed for {0} in '{1}': {2}" -f $entry.Upn, $r.Name, $_.Exception.Message)
                }
            }
        }

        # ---- Verify -----------------------------------------------------------------------------------
        if ($Mode -eq 'Remove') {
            $removedRows = @($results | Where-Object { $_.Status -eq 'Removed' })
            $reindexed = @{}
            foreach ($row in $removedRows) {
                $key = $row.Repository + '|' + $row.RepositoryType
                if (-not $reindexed.ContainsKey($key)) {
                    $repoObj = ($repos | Where-Object { ($_.Name + '|' + $_.Type) -eq $key } | Select-Object -First 1).Repository
                    $reindexed[$key] = Get-BackedUpUsers -Repository $repoObj
                }
                $after = Find-UserMatch -Upn $row.UserPrincipalName -Entities $reindexed[$key] -Property $matchProp
                if ($after.Status -eq 'NotInRepository') {
                    $row.Detail = 'Verified: user no longer listed in this repository'
                }
                else {
                    # The user can stay listed if only some workloads were removed; the flags show what is left.
                    $row.Status = 'RemovedButStillListed'
                    $row.Detail = ('User still listed after removal. Remaining flags: {0}' -f (Get-WorkloadFlags $after.Entity))
                }
            }

            try {
                $sessions = Get-RunSessions -Since $runStart
                if ($sessions.Count -gt 0) {
                    $sessions | Export-Csv -LiteralPath $sessionsPath -NoTypeInformation -Encoding UTF8
                    Write-Host ("{0} data management session(s) from this run written to {1}" -f $sessions.Count, $sessionsPath)
                }
            }
            catch { Write-Warning "Could not read data management sessions: $($_.Exception.Message)" }
        }
    }
    finally {
        if ($results.Count -gt 0) {
            $results | Export-Csv -LiteralPath $resultsPath -NoTypeInformation -Encoding UTF8
        }

        # ---- Summary ------------------------------------------------------------------------------------
        if ($results.Count -gt 0) {
            Write-Host ''
            Write-Host "Summary ($Mode)" -ForegroundColor Cyan
            foreach ($g in ($results | Group-Object Repository, RepositoryType)) {
                $counts = ($g.Group | Group-Object Status | Sort-Object Name | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join '  '
                Write-Host ("  {0}: {1}" -f $g.Name, $counts)
            }
            $notAnywhere = @($results | Group-Object UserPrincipalName | Where-Object { @($_.Group | Where-Object { $_.Status -ne 'NotInRepository' }).Count -eq 0 })
            Write-Host ("  Users not found in any repository: {0}" -f $notAnywhere.Count)
            Write-Host "  Results: $resultsPath"
        }

        if (@($results | Where-Object { $_.Status -in @('Failed', 'Ambiguous', 'RemovedButStillListed') }).Count -gt 0 -and $script:ExitCode -eq 0) {
            $script:ExitCode = 1
        }
        if ($transcriptStarted) { try { Stop-Transcript | Out-Null } catch { } }
    }
}

#endregion

# Run only when executed, not when dot-sourced (". .\vb365_remove_legacy_user_data.ps1" loads the
# functions for testing without running anything).
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Get-Command Get-VBORepository -ErrorAction SilentlyContinue)) {
        try { Import-Module Veeam.Archiver.PowerShell -ErrorAction Stop }
        catch { Write-Error "Veeam.Archiver.PowerShell module not available. Run this on the VB365 server. $($_.Exception.Message)"; exit 2 }
    }
    Invoke-VB365LegacyUserDataRemoval @PSBoundParameters
    if ($script:ExitCode -ne 0) { exit $script:ExitCode }
}
