# Various Powershell Scripts

### map_share.ps1

This scripts imports multiple shares into Veeam Backup and Replication in one go by reading the individual shares in \\host\share format from a text file. 

Please see https://helpcenter.veeam.com/docs/backup/powershell/add-vbrnassmbserver.html?ver=100 for full details on the command and note that not all options have been included. For example the script defaults to 'medium' on Backup IO control. 

This script has no association with Veeam.

## Azure_asssessment.ps1

Script to pull down the configuration of a Azure environment including:

- Subscriptions
- Tenants
- Resource groups
- VM information (not including disk info yet)
- Managed Disks
- Scans storage accounts for attached and unattached unmanaged disks

As well as the backup environment if present:

- Policies
- Jobs

NOTE: This is still in development.
## azure_environment_assessment.ps1

Read-only discovery of an Azure estate ahead of designing a Veeam backup solution. It covers every Veeam-protectable Azure workload: VMs and disks, Azure SQL Database, SQL Managed Instance, Cosmos DB, Azure Files, Blob storage accounts, and virtual network configuration, plus optional AKS, Azure VMware Solution and Entra ID modules. Every resource is placed in its environment (subscription, region, vNet and subnet) and tagged with how it is reached on the network, so worker placement and private connectivity can be designed straight from the output.

This script was **generated from a prompt** in the [awesome-veeam-prompts](https://github.com/shapedthought/awesome-veeam-prompts) repo: [VBAz-AzureEnvironmentAssessment](https://github.com/shapedthought/awesome-veeam-prompts/tree/main/VBAz-AzureEnvironmentAssessment). The prompt and its workload map are the source of truth, and the README there explains the outputs, parameters and known gaps. If you change behaviour here, feed the change back into the prompt.

```powershell
.\azure_environment_assessment.ps1                                   # default modules, all subscriptions
.\azure_environment_assessment.ps1 -Modules vm,vnet -SubscriptionId <id>   # start small
.\azure_environment_assessment.ps1 -BackupAssessment -Anonymise
```

Tests (Pester 5, no Azure connection, Az cmdlets mocked):

```powershell
Invoke-Pester -Path ./azure_environment_assessment.Tests.ps1 -Output Detailed
```

NOTE: It passes its 36 mocked Pester tests but has not yet been run against a real Azure tenant. Test it on one subscription first and compare a few rows with the portal. A wrong Az property name shows up as a blank column, not an error. Requires the Az PowerShell module and Reader on each subscription.

With `-Anonymise`, every file the script writes is anonymised, and so is the script's own console output. Output printed directly by Azure tools (for example Az error text or the `Connect-AzAccount` sign-in prompt) can still contain names, so **do not record a transcript of an anonymised run** (`Start-Transcript`, terminal logging) if the transcript will leave the organisation.

This script has no association with Veeam.

## vb365_remove_legacy_user_data.ps1

Removes backed-up user data (mailbox, archive mailbox, OneDrive, personal sites) from legacy Veeam Backup for Microsoft 365 repositories for a CSV of UPNs, using the supported `Remove-VBOEntityData` cmdlet. Typical use is clean-up after users have moved to Veeam Data Cloud. Primary and backup copy (`-LongTerm`) repositories are both supported.

This script was **generated from a prompt** in the [awesome-veeam-prompts](https://github.com/shapedthought/awesome-veeam-prompts) repo: [VB365-RemoveLegacyUserData](https://github.com/shapedthought/awesome-veeam-prompts/tree/main/VB365-RemoveLegacyUserData). The prompt and its cmdlet contract are the source of truth. If you change behaviour here, feed the change back into the prompt.

It is read-only by default. Users are matched on UPN against the backed-up data, so users already deleted from Entra ID are still found, and a UPN that matches more than one backed-up user is an error, never a guess.

```powershell
# 1. Inventory (read-only)
.\vb365_remove_legacy_user_data.ps1 -UsersCsv .\users.csv -RepositoryName "Legacy Repository" -Mailbox -ArchiveMailbox -OneDrive -Sites
# 2. Preview (Remove-VBOEntityData -WhatIf)
.\vb365_remove_legacy_user_data.ps1 -Mode Preview -UsersCsv .\users.csv -RepositoryName "Legacy Repository" -Mailbox -ArchiveMailbox -OneDrive -Sites
# 3. Canary removal of one non-critical user, then check it in Veeam Explorer
.\vb365_remove_legacy_user_data.ps1 -Mode Remove -Limit 1 -UsersCsv .\canary.csv -RepositoryName "Legacy Repository" -Mailbox -ArchiveMailbox -OneDrive -Sites
# 4. Full removal (asks you to type the user count first)
.\vb365_remove_legacy_user_data.ps1 -Mode Remove -Force -UsersCsv .\users.csv -RepositoryName "Legacy Repository" -LongTermRepositoryName "Azure Archive" -Mailbox -ArchiveMailbox -OneDrive -Sites
```

Tests (Pester 5, no VB365 server, Veeam cmdlets mocked):

```powershell
Invoke-Pester -Path ./vb365_remove_legacy_user_data.Tests.ps1 -Output Detailed
```

NOTE: It passes its 22 mocked Pester tests but has not yet been run against a real VB365 server. The property names on Veeam objects are undocumented, so the script finds them with `Get-Member` and stops if the email/UPN property is unclear (use `-MatchProperty`). Run Inventory first and compare a few rows with the VB365 console. **Removal is irreversible.** Disable the legacy jobs first, and note that immutable repositories are skipped because their data has to age out through retention. Run on the VB365 server with the `Veeam.Archiver.PowerShell` module.

This script has no association with Veeam.
