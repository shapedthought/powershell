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

NOTE: It passes its 20 mocked Pester tests but has not yet been run against a real Azure tenant. Test it on one subscription first and compare a few rows with the portal. A wrong Az property name shows up as a blank column, not an error. Requires the Az PowerShell module and Reader on each subscription.

This script has no association with Veeam.
