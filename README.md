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

As well as the backup environment if present:

- Policies
- Jobs

NOTE: This is still in development.