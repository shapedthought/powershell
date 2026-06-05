<#
MIT License

Copyright (c) 2026 Edward Howard

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

<#
.Synopsis
    Azure assessment on environmental and backup environments
.DESCRIPTION
    Script to get information on an Azure environment including
    infrastructure and backup if in use.
    Backup assessment can be enabled by adding the -BackupAssessment $true flag.
    Requires the Azure PowerShell module installed.
.PARAMETER BackupAssessment
    Flag to enable or disable backup assessment - default is false
.PARAMETER Anonymise
    Flag to hash sensitive fields (VM names, IPs, resource groups, etc.) in all output CSVs
.EXAMPLE
    .\azure_assessment.ps1
    .\azure_assessment.ps1 -BackupAssessment $true
    .\azure_assessment.ps1 -Anonymise
    .\azure_assessment.ps1 -BackupAssessment $true -Anonymise
#>
[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Please state if backup is required")]
    [bool]$BackupAssessment = $false,
    [Parameter(HelpMessage = "Hash sensitive fields in output CSVs")]
    [switch]$Anonymise
)

function Get-Hash {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash  = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-').Substring(0, 8).ToLower()
}

function Mask {
    param([string]$Value)
    if ($script:Anonymise) { return Get-Hash $Value }
    return $Value
}

function AzureAssessment {
    [CmdletBinding()]
    param(
        [bool]$BackupAssessment = $false,
        [switch]$Anonymise
    )

    # Check if Azure PowerShell module is installed
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Write-Error "Azure PowerShell module is not installed. Please install it using: Install-Module -Name Az -AllowClobber -Scope CurrentUser"
        return
    }

    # Confirmation
    Write-Host "This script will gather information on your Azure environment" -ForegroundColor Cyan
    $confirm = Read-Host "Please confirm that you understand this is not a Veeam tool and there is no support for this script. Type 'yes' to continue"
    if ($confirm -ne "yes") {
        Write-Host "Exiting script" -ForegroundColor Yellow
        return
    }

    if ($Anonymise) {
        Write-Host "Anonymise mode enabled — sensitive fields will be SHA256-hashed in all output." -ForegroundColor Yellow
    }

    # Expose anonymise flag to the Mask helper
    $script:Anonymise = $Anonymise

    try {
        Write-Host "Starting Azure Assessment" -ForegroundColor Green

        Write-Host "Connecting to Azure..." -ForegroundColor Cyan
        $azConnection = Connect-AzAccount -ErrorAction Stop
        if (-not $azConnection) {
            Write-Error "Failed to connect to Azure. Please check your credentials and try again."
            return
        }

        Write-Host "Gathering subscription info" -ForegroundColor Cyan
        $subscriptions = Get-AzSubscription
        if (-not $subscriptions) {
            Write-Warning "No subscriptions found for this account."
            return
        }

        $outputDir = ".\AzureAssessment_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $outputDir | Out-Null

        # Subscriptions — mask name and tenant ID
        $subscriptions | Select-Object Id, @{N='Name';E={Mask $_.Name}}, State, @{N='TenantId';E={Mask $_.TenantId}} |
            Export-Csv -Path "$outputDir\subscriptions.csv" -NoTypeInformation

        Write-Host "Gathering Tenant Info" -ForegroundColor Cyan
        Get-AzTenant | Select-Object Id, @{N='Domains';E={Mask $_.Domains}} |
            Export-Csv -Path "$outputDir\Tenants.csv" -NoTypeInformation

        $allResourceGroups = @()
        $allDisks          = @()
        $allVaults         = @()

        foreach ($subscription in $subscriptions) {
            Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Cyan
            try {
                Select-AzSubscription -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null

                Write-Host "  Gathering Resource Group Info" -ForegroundColor Cyan
                $rgs = @(Get-AzResourceGroup -ErrorAction SilentlyContinue)
                $allResourceGroups += $rgs | Select-Object @{N='ResourceGroupName';E={Mask $_.ResourceGroupName}}, Location, ProvisioningState

                Write-Host "  Gathering Disk Info - Managed Disks" -ForegroundColor Cyan
                $disks = @(Get-AzDisk -ErrorAction SilentlyContinue)
                $allDisks += $disks | Select-Object @{N='Name';E={Mask $_.Name}}, @{N='ResourceGroupName';E={Mask $_.ResourceGroupName}}, Location, DiskSizeGB, Sku, OsType, DiskState

                # VM inventory
                Write-Host "  Gathering VM Info" -ForegroundColor Cyan
                $vms = @(Get-AzVM -ErrorAction Stop)
                if ($vms.Count -eq 0) {
                    Write-Warning "No VMs found in subscription $($subscription.Name)"
                    continue
                }

                $publicIps = @(Get-AzPublicIpAddress -ErrorAction SilentlyContinue)
                $nics      = @(Get-AzNetworkInterface -ErrorAction SilentlyContinue | Where-Object { $null -ne $_.VirtualMachine })

                $report = @()
                foreach ($vm in $vms) {
                    $primaryNicId = $vm.NetworkProfile.NetworkInterfaces[0].Id
                    $nic = $nics | Where-Object { $_.Id -eq $primaryNicId }

                    $publicIpAddress = ""
                    if ($nic) {
                        $nicIpConfigId = $nic.IpConfigurations[0].Id
                        $matchedIp = $publicIps | Where-Object { $_.IpConfiguration.Id -eq $nicIpConfigId }
                        if ($matchedIp) { $publicIpAddress = Mask $matchedIp.IpAddress }
                    }

                    $totalDiskCapacity = 0
                    foreach ($disk in $vm.StorageProfile.DataDisks) { $totalDiskCapacity += $disk.DiskSizeGB }

                    $report += New-Object PSObject -Property @{
                        VmName                   = Mask $vm.Name
                        ResourceGroupName        = Mask $vm.ResourceGroupName
                        Region                   = $vm.Location
                        VmSize                   = $vm.HardwareProfile.VmSize
                        VirtualNetwork           = if ($nic) { Mask $nic.IpConfigurations[0].Subnet.Id.Split("/")[-3] } else { "" }
                        Subnet                   = if ($nic) { Mask $nic.IpConfigurations[0].Subnet.Id.Split("/")[-1] } else { "" }
                        PrivateIpAddress         = if ($nic) { Mask $nic.IpConfigurations[0].PrivateIpAddress } else { "" }
                        PublicIPAddress          = $publicIpAddress
                        OsType                   = $vm.StorageProfile.OsDisk.OsType
                        NicName                  = if ($nic) { Mask $nic.Name } else { "" }
                        ApplicationSecurityGroup = if ($nic) { Mask $nic.IpConfigurations[0].ApplicationSecurityGroups.Id } else { "" }
                        OsDiskCapacity           = $vm.StorageProfile.OsDisk.DiskSizeGB
                        TotalDataDiskCapacity    = $totalDiskCapacity
                    }
                }

                $reportName = "$outputDir\vm_report_Subscription_$($subscription.Id).csv"
                $report | Export-CSV $reportName -NoTypeInformation
                Write-Host "  VM report exported to $reportName" -ForegroundColor Green

                if ($BackupAssessment -eq $true) {
                    $allVaults += @(Get-AzRecoveryServicesVault -ErrorAction SilentlyContinue)
                }

            } catch {
                Write-Error "Error processing subscription $($subscription.Name): $_"
            }
        }

        $allResourceGroups | Export-Csv -Path "$outputDir\resourcegroups.csv" -NoTypeInformation
        $allDisks          | Export-Csv -Path "$outputDir\Diskinfo.csv" -NoTypeInformation

        # Backup assessment
        if ($BackupAssessment -eq $true) {
            Write-Host "Gathering Backup Info, this can take a while" -ForegroundColor Cyan

            if (@($allVaults).Count -eq 0) {
                Write-Warning "No Recovery Services vaults found across all subscriptions."
            } else {
                foreach ($vault in $allVaults) {
                    Write-Host "Processing vault: $($vault.Name)" -ForegroundColor Cyan
                    try {
                        $vaultName = Mask $vault.Name
                        $rgName    = Mask $vault.ResourceGroupName

                        $policyName = "$outputDir\policies_$($vault.Name)_$($vault.ResourceGroupName).csv"
                        $jobName    = "$outputDir\jobs_$($vault.Name)_$($vault.ResourceGroupName).csv"
                        $itemsName  = "$outputDir\backup_items_$($vault.Name)_$($vault.ResourceGroupName).csv"

                        $containers = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -VaultId $vault.ID -ErrorAction SilentlyContinue

                        if ($containers) {
                            $report = @()
                            foreach ($container in $containers) {
                                try {
                                    $backupItems = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM -VaultId $vault.ID -ErrorAction SilentlyContinue

                                    foreach ($backupItem in $backupItems) {
                                        $report += New-Object PSObject -Property @{
                                            VmName              = Mask $backupItem.Name.Split(';')[-1]
                                            PolicyId            = $backupItem.PolicyId
                                            ProtectionState     = $backupItem.ProtectionState
                                            LastBackupStatus    = $backupItem.LastBackupStatus
                                            LatestRecoveryPoint = $backupItem.LatestRecoveryPoint
                                            ContainerName       = Mask $container.Name
                                            VaultName           = $vaultName
                                            ResourceGroup       = $rgName
                                        }
                                    }
                                } catch {
                                    Write-Error "Error processing backup container $($container.Name): $_"
                                }
                            }

                            $report | Export-CSV $itemsName -NoTypeInformation
                            Write-Host "  Backup items for vault $($vault.Name) exported to $itemsName" -ForegroundColor Green
                        } else {
                            Write-Warning "No backup containers found in vault $($vault.Name)"
                        }

                        Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $vault.Id -ErrorAction SilentlyContinue |
                            Select-Object @{N='Name';E={Mask $_.Name}}, WorkloadType, ScheduleRunFrequency, RetentionDays |
                            Export-Csv $policyName -NoTypeInformation
                        Write-Host "  Backup policies for vault $($vault.Name) exported to $policyName" -ForegroundColor Green

                        Get-AzRecoveryServicesBackupJob -VaultId $vault.Id -ErrorAction SilentlyContinue |
                            Select-Object @{N='WorkloadName';E={Mask $_.WorkloadName}}, Operation, Status, StartTime, EndTime, Duration |
                            Export-Csv $jobName -NoTypeInformation
                        Write-Host "  Backup jobs for vault $($vault.Name) exported to $jobName" -ForegroundColor Green

                    } catch {
                        Write-Error "Error processing Recovery Services vault $($vault.Name): $_"
                    }
                }
            }
        }

        Write-Host "Azure Assessment completed successfully! Results saved to $outputDir" -ForegroundColor Green

    } catch {
        Write-Error "An error occurred during the Azure Assessment: $_"
    }
}

try {
    AzureAssessment -BackupAssessment $BackupAssessment -Anonymise:$Anonymise
} catch {
    Write-Error "Error executing the AzureAssessment function: $_"
}
