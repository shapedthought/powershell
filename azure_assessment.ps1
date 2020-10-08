<#
.Synopsis
    Azure assessment on environmental and backup environments
.DESCRIPTION
    Script to get information on an Azure environment including
    infrastructure and backup if in use.
    Backup assessment can be disable by adding the -backupAssessment $false flag.
    Requires the Azure PowerShell module installed.
.EXAMPLE
    AzureAssessment()
#>
function AzureAssessment {
    [CmdletBinding()]
    param(
        [Parameter(HelpMessage = "Please state if backup is required")]
        [bool]$backupAssessment = $true
    )
    #Login
    Connect-AzAccount

    # Environmental information
    $subscription = Get-AzSubscription

    Get-AzSubscription | Export-Csv -Path .\subscriptions.csv -NoTypeInformation
    Get-AzTenant | Export-Csv -Path .\Tenants.csv -NoTypeInformation
    Get-AzResourceGroup | Export-Csv -Path .\resourcegroups.csv -NoTypeInformation
    foreach ($item in $subscription) {
        Select-AzSubscription -SubscriptionId $item.Id
        $reportName = "report_" + $item.Id + ".csv"
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
        $report | Export-CSV "$reportName"
    }
    # Backup assessment
    if ($backupAssessment -eq $true) {
        $vaults = Get-AzRecoveryServicesVault
        foreach ($item in $vaults) {
            $policyName = "policies_" + $item.SubscriptionId + ".csv"
            $jobName = "job_" + $item.SubscriptionId + ".csv"
            # Set-AzRecoveryServicesVaultContext -Vault $item > still figuring out if this is needed
            Get-AzRecoveryServicesBackupProtectionPolicy | Export-Csv $policyName
            Get-AzRecoveryServicesBackupJob -VaultId $item.Id | Export-Csv $jobName
        }
    }
}