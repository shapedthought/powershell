<#
.Synopsis
    Azure assessment on environmental and backup environments
.DESCRIPTION
    Script to get information on an Azure environment including
    infrastructure and backup if in use.
    Backup assessment can be disable by adding the -backupAssessment $false flag.
    Requires the Azure PowerShell module installed.
.EXAMPLE
    . .\azure_assessment.ps1
    AzureAssessment
#>
function AzureAssessment {
    [CmdletBinding()]
    param(
        [Parameter(HelpMessage = "Please state if backup is required")]
        [bool]$backupAssessment = $true
    )
    #Login
    Connect-AzAccount
    Write-Host("Gathering subscription info")
    # Environmental information
    $subscription = Get-AzSubscription

    Get-AzSubscription | Export-Csv -Path .\subscriptions.csv -NoTypeInformation
    Write-Host("Gathering Tenant Info")
    Get-AzTenant | Export-Csv -Path .\Tenants.csv -NoTypeInformation
    Write-Host("Gathering Resource Group Info")
    Get-AzResourceGroup | Export-Csv -Path .\resourcegroups.csv -NoTypeInformation
    Write-Host("Gathering Disk Info - Managed Disk")
    Get-AzDisk | Export-Csv -Path .\Diskifno.csv -NoTypeInformation
    Write-Host("Scanning Storage Accounts for unmanged Disks")
    $storageAccounts = Get-AzStorageAccount
    foreach ($storageAccount in $storageAccounts) {
        Write-Host("Checking Storage Account: " + $storageAccount.StorageAccountName)
        $info = "" | Select-Object Account, Container, Size, IsDeleted, BlobType, Name, Lease
        $check = $False
        $storageReport = @()
        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName)[0].Value
        $context = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageKey
        $containers = Get-AzStorageContainer -Context $context
        foreach ($container in $containers) {
            Write-Host("Scanning container " + $container.Name + " for .vhd")
            $blobs = Get-AzStorageBlob -Container $container.Name -Context $context
            $vhd = $blobs | Where-Object { $_.BlobType -eq 'PageBlob' -and $_.Name.EndsWith('.vhd') }
            if($vhd.Length -gt 0) {
                foreach ($item in $vhd) {
                    $info.Account = $storageAccount.StorageAccountName
                    $info.Container = $container.Name
                    $info.Size = $item.Length / 1GB
                    $info.IsDeleted = $item.IsDeleted
                    $info.BlobType = $item.BlobType
                    $info.Name = $item.Name
                    $info.Lease = $item.BlobProperties.LeaseStatus
                    $storageReport += $info
                }
                if($check -eq $False) {
                    $check = $True
                }
            } else {
                Write-Host("No .vhd in " + $container.Name)
            }
        }
        if($check) {
            Write-Host("Writing Report for Storage Account" + $storageAccount.StorageAccountName)
            Write-Host("")
            $reportName = ".\vhd-" + $storageAccount.StorageAccountName + ".csv"
            $storageReport | Export-Csv -Path $reportName -NoTypeInformation
        } else {
            Write-Host("No .vhd in Storage Account" + $storageAccount.StorageAccountName)
            Write-Host("")
        }
    }
    Write-Host("Gathering VM Info")
    foreach ($item in $subscription) {
        Select-AzSubscription -SubscriptionId $item.Id
        $reportName = "vm_report_Subscription_" + $item.Id + ".csv"
        $report = @()
        $vms = Get-AzVM
        $publicIps = Get-AzPublicIpAddress
        $nics = Get-AzNetworkInterface | Where-Object { $null -NE $_.VirtualMachine } 
        foreach ($nic in $nics) { 
            $info = "" | Select-Object VmName, ResourceGroupName, Region, VmSize, VirtualNetwork, Subnet, PrivateIpAddress, OsType, PublicIPAddress, NicName, ApplicationSecurityGroup 
            $vm = $vms | Where-Object -Property Id -eq $nic.VirtualMachine.id 
            foreach ($publicIp in $publicIps) { 
                if ($nic.IpConfigurations.id -eq $publicIp.ipconfiguration.Id) {
                    $info.PublicIPAddress = $publicIp.ipaddress
                } 
            } 
            $info.OsType = $vm.StorageProfile.OsDisk.OsType 
            $info.VMName = $vm.Name 
            $info.ResourceGroupName = $vm.ResourceGroupName 
            $info.Region = $vm.Location 
            $info.VmSize = $vm.HardwareProfile.VmSize
            $info.VirtualNetwork = $nic.IpConfigurations.subnet.Id.Split("/")[-3] 
            $info.Subnet = $nic.IpConfigurations.subnet.Id.Split("/")[-1] 
            $info.PrivateIpAddress = $nic.IpConfigurations.PrivateIpAddress 
            $info.NicName = $nic.Name 
            $info.ApplicationSecurityGroup = $nic.IpConfigurations.ApplicationSecurityGroups.Id 
            $report += $info 
        } 
        $report | Format-Table VmName, ResourceGroupName, Region, VmSize, VirtualNetwork, Subnet, PrivateIpAddress, OsType, PublicIPAddress, NicName, ApplicationSecurityGroup 
        $report | Export-CSV "$reportName" -NoTypeInformation
    }
    # Backup assessment
    if ($backupAssessment -eq $true) {

        Write-Host("Gathering Backup info Info, this can take a while")
        $vaults = Get-AzRecoveryServicesVault
        foreach ($item in $vaults) {
            $policyName = "policies_" + $item.SubscriptionId + ".csv"
            $jobName = "job_" + $item.SubscriptionId + ".csv"
            Set-AzRecoveryServicesVaultContext -Vault $item
            Get-AzRecoveryServicesBackupProtectionPolicy | Export-Csv $policyName -NoTypeInformation
            Get-AzRecoveryServicesBackupJob -VaultId $item.Id | Export-Csv $jobName -NoTypeInformation
        }
    }
}

