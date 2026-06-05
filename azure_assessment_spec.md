# Azure Assessment Script — Specification

This document describes the requirements for an Azure environment assessment PowerShell script. It is intended to be used as a prompt or reference for recreating the script with an LLM or from scratch.

---

## Purpose

A single-file PowerShell script that connects to Azure, collects infrastructure and backup data across all accessible subscriptions, and exports the results to CSV files. It is an unofficial pre-sales discovery tool — not a supported product.

---

## Prerequisites

- PowerShell 5.1 or later
- Azure PowerShell (`Az`) module:
  ```powershell
  Install-Module -Name Az -AllowClobber -Scope CurrentUser
  ```

---

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-BackupAssessment` | `bool` | `$false` | When `$true`, collects Recovery Services vault data (backup items, policies, jobs) |
| `-Anonymise` | `switch` | off | When present, hashes sensitive string fields in all output CSVs |

---

## Invocation Examples

```powershell
.\azure_assessment.ps1
.\azure_assessment.ps1 -BackupAssessment $true
.\azure_assessment.ps1 -Anonymise
.\azure_assessment.ps1 -BackupAssessment $true -Anonymise
```

---

## Execution Flow

1. **Module check** — verify `Az.Accounts` is installed; exit with a clear error message if not.
2. **Consent prompt** — print a warning that this is not a supported Veeam tool; require the user to type `yes` to proceed.
3. **Login** — call `Connect-AzAccount` interactively.
4. **Get subscriptions** — call `Get-AzSubscription`; exit with a warning if none are found.
5. **Create output directory** — named `.\AzureAssessment_<yyyyMMdd_HHmmss>\`.
6. **Export top-level data** — subscriptions and tenants (see outputs below).
7. **Per-subscription loop** — for each subscription, call `Select-AzSubscription` then collect:
   - Resource groups
   - Managed disks
   - VM inventory (see VM logic below)
   - Recovery Services vaults (only if `-BackupAssessment $true`)
8. **Export aggregated data** — write the combined resource group and disk arrays to CSV after the loop completes.
9. **Backup assessment** (if `-BackupAssessment $true`) — iterate all collected vaults and export backup items, policies, and jobs (see below).

---

## VM Inventory Logic

- Fetch all VMs in the subscription with `Get-AzVM`.
- Fetch all NICs attached to a VM with `Get-AzNetworkInterface | Where-Object { $_.VirtualMachine -ne $null }`.
- Fetch all public IPs with `Get-AzPublicIpAddress`.
- For each VM, match on **primary NIC only** using `$vm.NetworkProfile.NetworkInterfaces[0].Id` — one row per VM.
- Resolve public IP by matching the NIC's first IP configuration ID against `$publicIp.IpConfiguration.Id`.
- Sum `DiskSizeGB` across all data disks for `TotalDataDiskCapacity`.
- VMs with no matching NIC should still appear in the report with empty network fields.

---

## Anonymise Mode

When `-Anonymise` is set, all sensitive string fields must be passed through a helper function before writing to CSV.

**Hashing approach:** SHA256 via `[System.Security.Cryptography.SHA256]`, truncated to the first 8 hex characters, lowercased. Hashing must be deterministic — the same input always produces the same output — so records can be cross-referenced across CSV files.

**Fields to hash:**

| Output file | Fields hashed |
|-------------|--------------|
| `subscriptions.csv` | `Name`, `TenantId` |
| `Tenants.csv` | `Domains` |
| `resourcegroups.csv` | `ResourceGroupName` |
| `Diskinfo.csv` | `Name`, `ResourceGroupName` |
| `vm_report_*.csv` | `VmName`, `ResourceGroupName`, `VirtualNetwork`, `Subnet`, `PrivateIpAddress`, `PublicIPAddress`, `NicName`, `ApplicationSecurityGroup` |
| `backup_items_*.csv` | `VmName`, `ContainerName`, `VaultName`, `ResourceGroup` |
| `policies_*.csv` | `Name` |
| `jobs_*.csv` | `WorkloadName` |

**Fields never hashed:** regions, VM sizes, OS types, disk sizes, subscription IDs, timestamps, status/state values.

---

## Output Files

All files are written to the timestamped output directory.

### Always produced

| File | Contents |
|------|----------|
| `subscriptions.csv` | `Id`, `Name`, `State`, `TenantId` |
| `Tenants.csv` | `Id`, `Domains` |
| `resourcegroups.csv` | `ResourceGroupName`, `Location`, `ProvisioningState` — aggregated across all subscriptions |
| `Diskinfo.csv` | `Name`, `ResourceGroupName`, `Location`, `DiskSizeGB`, `Sku`, `OsType`, `DiskState` — aggregated across all subscriptions |
| `vm_report_Subscription_<subscriptionId>.csv` | One file per subscription — see fields below |

**VM report fields:** `VmName`, `ResourceGroupName`, `Region`, `VmSize`, `VirtualNetwork`, `Subnet`, `PrivateIpAddress`, `PublicIPAddress`, `OsType`, `NicName`, `ApplicationSecurityGroup`, `OsDiskCapacity`, `TotalDataDiskCapacity`

### With `-BackupAssessment $true`

One set of files per Recovery Services vault, named using the real (non-hashed) vault name and resource group for the filename:

| File | Contents |
|------|----------|
| `backup_items_<vault>_<rg>.csv` | `VmName`, `PolicyId`, `ProtectionState`, `LastBackupStatus`, `LatestRecoveryPoint`, `ContainerName`, `VaultName`, `ResourceGroup` |
| `policies_<vault>_<rg>.csv` | `Name`, `WorkloadType`, `ScheduleRunFrequency`, `RetentionDays` |
| `jobs_<vault>_<rg>.csv` | `WorkloadName`, `Operation`, `Status`, `StartTime`, `EndTime`, `Duration` |

---

## Error Handling

- Wrap the entire assessment body in a `try/catch`; print a descriptive error and continue where possible.
- Per-subscription and per-vault failures should be caught individually so a single inaccessible subscription does not abort the whole run.
- Use `-ErrorAction SilentlyContinue` for supplementary data (NICs, public IPs, disks) where absence is non-fatal.
- Use `-ErrorAction Stop` for critical calls (`Connect-AzAccount`, `Select-AzSubscription`, `Get-AzVM`) so failures are caught by the enclosing `try/catch`.

---

## Code Structure

- Two small top-level helper functions (`Get-Hash`, `Mask`) defined before the main function.
- One main function `AzureAssessment` containing all logic, called at the bottom of the script with the script-level parameters forwarded.
- `$script:Anonymise` used to share the flag between the main function and the `Mask` helper.
- Progress messages use `Write-Host` with colour coding: Cyan for progress, Green for success, Yellow for warnings/skips.
