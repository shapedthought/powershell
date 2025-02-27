<#
.Synopsis
    Azure assessment on environmental and backup environments
.DESCRIPTION
    Script to get information on an Azure environment including
    infrastructure and backup if in use.
    Backup assessment can be enabled by adding the -backupAssessment $true flag.
    Requires the Azure PowerShell module installed.
.PARAMETER BackupAssessment
    Flag to enable or disable backup assessment - default is false
.PARAMETER AssessUnmanaged
    Flag to enable or disable unmanaged disk assessment - default is false
.EXAMPLE
    .\azure_assessment.ps1
    .\azure_assessment.ps1 -BackupAssessment $true
    .\azure_assessment.ps1 -AssessUnmanaged $true
    .\azure_assessment.ps1 -BackupAssessment $true -AssessUnmanaged $true
#>
[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Please state if backup is required")]
    [bool]$BackupAssessment = $false,
    [Parameter(HelpMessage = "Please state if unmanaged disks assessment is required")]
    [bool]$AssessUnmanaged = $false
)

function AzureAssessment {
    [CmdletBinding()]
    param(
        [Parameter(HelpMessage = "Please state if backup is required")]
        [bool]$BackupAssessment = $false,
        [Parameter(HelpMessage = "Please state if unmanaged disks assessment is required")]
        [bool]$AssessUnmanaged = $false
    )
    
    #Check if Azure PowerShell module is installed
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Write-Error "Azure PowerShell module is not installed. Please install it using: Install-Module -Name Az -AllowClobber -Scope CurrentUser"
        return
    }
    
    #Confirmation
    Write-Host "This script will gather information on your Azure environment" -ForegroundColor Cyan
    $confirm = Read-Host "Please confirm that you understand this is not a Veeam tool and there is no support for this script. Type 'yes' to continue"
    if ($confirm -ne "yes") {
        Write-Host "Exiting script" -ForegroundColor Yellow
        return
    }
    
    try {
        Write-Host "Starting Azure Assessment" -ForegroundColor Green
        
        #Login
        Write-Host "Connecting to Azure..." -ForegroundColor Cyan
        $azConnection = Connect-AzAccount -ErrorAction Stop
        if (-not $azConnection) {
            Write-Error "Failed to connect to Azure. Please check your credentials and try again."
            return
        }
        
        Write-Host "Gathering subscription info" -ForegroundColor Cyan
        # Environmental information
        $subscriptions = Get-AzSubscription
        if (-not $subscriptions) {
            Write-Warning "No subscriptions found for this account."
            return
        }
        
        # Create output directory if it doesn't exist
        $outputDir = ".\AzureAssessment_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir | Out-Null
        }
        
        $subscriptions | Export-Csv -Path "$outputDir\subscriptions.csv" -NoTypeInformation
        Write-Host "Gathering Tenant Info" -ForegroundColor Cyan
        Get-AzTenant | Export-Csv -Path "$outputDir\Tenants.csv" -NoTypeInformation
        Write-Host "Gathering Resource Group Info" -ForegroundColor Cyan
        Get-AzResourceGroup | Export-Csv -Path "$outputDir\resourcegroups.csv" -NoTypeInformation
        Write-Host "Gathering Disk Info - Managed Disk" -ForegroundColor Cyan
        Get-AzDisk | Export-Csv -Path "$outputDir\Diskinfo.csv" -NoTypeInformation
        
        if ($AssessUnmanaged -eq $true) {
            Write-Host "Scanning Storage Accounts for unmanaged Disks" -ForegroundColor Cyan
            $storageAccounts = Get-AzStorageAccount
            
            if ($storageAccounts) {
                foreach ($storageAccount in $storageAccounts) {
                    Write-Host "Checking Storage Account: $($storageAccount.StorageAccountName)" -ForegroundColor Cyan
                    $check = $False
                    $storageReport = @()
                    
                    try {
                        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName -ErrorAction Stop)[0].Value
                        $context = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageKey -ErrorAction Stop
                        
                        $containers = Get-AzStorageContainer -Context $context -ErrorAction Stop
                        foreach ($container in $containers) {
                            Write-Host "Scanning container $($container.Name) for .vhd" -ForegroundColor Cyan
                            $blobs = Get-AzStorageBlob -Container $container.Name -Context $context -ErrorAction Stop
                            $vhd = $blobs | Where-Object { $_.BlobType -eq 'PageBlob' -and $_.Name.EndsWith('.vhd') }
                            
                            if ($vhd -and $vhd.Count -gt 0) {
                                foreach ($item in $vhd) {
                                    # Create a new object for each item
                                    $info = New-Object PSObject -Property @{
                                        Account     = $storageAccount.StorageAccountName
                                        Container   = $container.Name
                                        Size        = [math]::Round($item.Length / 1GB, 2)
                                        IsDeleted   = $item.IsDeleted
                                        BlobType    = $item.BlobType
                                        Name        = $item.Name
                                        Lease       = $item.BlobProperties.LeaseStatus
                                    }
                                    $storageReport += $info
                                }
                                if ($check -eq $False) {
                                    $check = $True
                                }
                            } else {
                                Write-Host "No .vhd in $($container.Name)" -ForegroundColor Yellow
                            }
                        }
                        
                        if ($check) {
                            Write-Host "Writing Report for Storage Account $($storageAccount.StorageAccountName)" -ForegroundColor Green
                            $reportName = "$outputDir\vhd-$($storageAccount.StorageAccountName).csv"
                            $storageReport | Export-Csv -Path $reportName -NoTypeInformation
                        } else {
                            Write-Host "No .vhd in Storage Account $($storageAccount.StorageAccountName)" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Error "Error processing storage account $($storageAccount.StorageAccountName): $_"
                    }
                }
            } else {
                Write-Warning "No storage accounts found."
            }
        }
        
        Write-Host "Gathering VM Info" -ForegroundColor Cyan
        foreach ($subscription in $subscriptions) {
            Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Cyan
            try {
                Select-AzSubscription -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null
                
                $reportName = "$outputDir\vm_report_Subscription_$($subscription.Id).csv"
                $report = @()
                
                $vms = Get-AzVM -ErrorAction Stop
                if ($vms.Count -eq 0) {
                    Write-Warning "No VMs found in subscription $($subscription.Name)"
                    continue
                }
                
                $publicIps = Get-AzPublicIpAddress -ErrorAction SilentlyContinue
                $nics = Get-AzNetworkInterface -ErrorAction SilentlyContinue | Where-Object { $null -NE $_.VirtualMachine }
                
                foreach ($nic in $nics) {
                    $vm = $vms | Where-Object -Property Id -eq $nic.VirtualMachine.id
                    
                    if ($vm) {
                        # Create a new object for each VM
                        $info = New-Object PSObject -Property @{
                            VmName                   = $vm.Name
                            ResourceGroupName        = $vm.ResourceGroupName
                            Region                   = $vm.Location
                            VmSize                   = $vm.HardwareProfile.VmSize
                            VirtualNetwork           = $nic.IpConfigurations.subnet.Id.Split("/")[-3]
                            Subnet                   = $nic.IpConfigurations.subnet.Id.Split("/")[-1]
                            PrivateIpAddress         = $nic.IpConfigurations.PrivateIpAddress
                            OsType                   = $vm.StorageProfile.OsDisk.OsType
                            PublicIPAddress          = ""
                            NicName                  = $nic.Name
                            ApplicationSecurityGroup = $nic.IpConfigurations.ApplicationSecurityGroups.Id
                            OsDiskCapacity           = $vm.StorageProfile.OsDisk.DiskSizeGB
                            TotalDataDiskCapacity    = 0
                        }
                        
                        # Set public IP if available
                        foreach ($publicIp in $publicIps) {
                            if ($nic.IpConfigurations.id -eq $publicIp.ipconfiguration.Id) {
                                $info.PublicIPAddress = $publicIp.ipaddress
                            }
                        }
                        
                        # Calculate total disk capacity
                        $totalDiskCapacity = 0
                        foreach ($disk in $vm.StorageProfile.DataDisks) {
                            $totalDiskCapacity += $disk.DiskSizeGB
                        }
                        $info.TotalDataDiskCapacity = $totalDiskCapacity
                        
                        $report += $info
                    }
                }
                
                $report | Export-CSV $reportName -NoTypeInformation
                Write-Host "VM report for subscription $($subscription.Name) exported to $reportName" -ForegroundColor Green
                
            } catch {
                Write-Error "Error processing subscription $($subscription.Name): $_"
            }
        }
        
        # Backup assessment
        if ($BackupAssessment -eq $true) {
            Write-Host "Gathering Backup Info, this can take a while" -ForegroundColor Cyan
            try {
                $vaults = Get-AzRecoveryServicesVault -ErrorAction Stop
                
                if ($vaults.Count -eq 0) {
                    Write-Warning "No Recovery Services vaults found."
                } else {
                    foreach ($vault in $vaults) {
                        Write-Host "Processing vault: $($vault.Name)" -ForegroundColor Cyan
                        try {
                            $policyName = "$outputDir\policies_$($vault.Name)_$($vault.ResourceGroupName).csv"
                            $jobName = "$outputDir\jobs_$($vault.Name)_$($vault.ResourceGroupName).csv"
                            $itemsName = "$outputDir\backup_items_$($vault.Name)_$($vault.ResourceGroupName).csv"
                            
                            # Set vault context
                            Set-AzRecoveryServicesVaultContext -Vault $vault -ErrorAction Stop
                            
                            # Get containers
                            $containers = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -VaultId $vault.ID -ErrorAction SilentlyContinue
                            
                            if ($containers) {
                                $report = @()
                                foreach ($container in $containers) {
                                    try {
                                        $backupItems = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM -VaultId $vault.ID -ErrorAction SilentlyContinue
                                        
                                        foreach ($backupItem in $backupItems) {
                                            $name = $backupItem.Name.Split(';')[-1]
                                            
                                            # Create a new object for each backup item
                                            $itemInfo = New-Object PSObject -Property @{
                                                VmName             = $name
                                                PolicyId           = $backupItem.PolicyId
                                                ProtectionState    = $backupItem.ProtectionState
                                                LastBackupStatus   = $backupItem.LastBackupStatus
                                                LatestRecoveryPoint = $backupItem.LatestRecoveryPoint
                                                ContainerName      = $container.Name
                                                VaultName          = $vault.Name
                                                ResourceGroup      = $vault.ResourceGroupName
                                            }
                                            
                                            $report += $itemInfo
                                        }
                                    } catch {
                                        Write-Error "Error processing backup container $($container.Name): $_"
                                    }
                                }
                                
                                $report | Export-CSV $itemsName -NoTypeInformation
                                Write-Host "Backup items for vault $($vault.Name) exported to $itemsName" -ForegroundColor Green
                            } else {
                                Write-Warning "No backup containers found in vault $($vault.Name)"
                            }
                            
                            # Get policies
                            Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $vault.Id -ErrorAction SilentlyContinue | 
                                Export-Csv $policyName -NoTypeInformation
                            Write-Host "Backup policies for vault $($vault.Name) exported to $policyName" -ForegroundColor Green
                            
                            # Get jobs
                            Get-AzRecoveryServicesBackupJob -VaultId $vault.Id -ErrorAction SilentlyContinue | 
                                Export-Csv $jobName -NoTypeInformation
                            Write-Host "Backup jobs for vault $($vault.Name) exported to $jobName" -ForegroundColor Green
                            
                        } catch {
                            Write-Error "Error processing Recovery Services vault $($vault.Name): $_"
                        }
                    }
                }
            } catch {
                Write-Error "Error gathering backup information: $_"
            }
        }
        
        Write-Host "Azure Assessment completed successfully! Results saved to $outputDir" -ForegroundColor Green
        
    } catch {
        Write-Error "An error occurred during the Azure Assessment: $_"
    }
}

# Execute the function with the script parameters
try {
    AzureAssessment -BackupAssessment $BackupAssessment -AssessUnmanaged $AssessUnmanaged
} catch {
    Write-Error "Error executing the AzureAssessment function: $_"
}
