<#
.Synopsis
    Azure assessment on IaaS virtual machine compute and storage using modern, recommended cmdlets.
.DESCRIPTION
    Script to get detailed information on an Azure VM environment. It uses the modern Get-AzComputeResourceSku cmdlet
    for a performant and future-proof way to gather VM specifications, OS details, and disk configurations.
    Produces a single CSV file per subscription.
.EXAMPLE
    # In Azure Cloud Shell, save this script to a file (e.g., azure_vm_assessment_final.ps1)
    # and then run it directly:
    #
    # .\azure_vm_assessment_final.ps1
#>
[CmdletBinding()]
param()

function AzureAssessment {
    [CmdletBinding()]
    param()
    
    #Check if Azure context exists (it always should in Cloud Shell)
    if (-not (Get-AzContext)) {
        Write-Error "Not logged into Azure. Please log in using Connect-AzAccount."
        return
    }
    
    #Confirmation
    Write-Host "This script will gather information on your Azure VM environment" -ForegroundColor Cyan
    $confirm = Read-Host "Please confirm that you understand this is not a Veeam tool and there is no support for this script. Type 'yes' to continue"
    if ($confirm -ne "yes") {
        Write-Host "Exiting script" -ForegroundColor Yellow
        return
    }
    
    try {
        Write-Host "Starting Azure VM and Storage Assessment" -ForegroundColor Green
        
        Write-Host "Gathering subscription info from current context..." -ForegroundColor Cyan
        $subscriptions = Get-AzSubscription
        if (-not $subscriptions) {
            Write-Warning "No subscriptions found for this account."
            return
        }
        
        # Create output directory in your clouddrive
        $outputDir = ".\AzureAssessment_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir | Out-Null
        }
        
        $subscriptions | Export-Csv -Path "$outputDir\subscriptions.csv" -NoTypeInformation
        $tenant = Get-AzContext | Select-Object -ExpandProperty Tenant
        Get-AzTenant | Export-Csv -Path "$outputDir\Tenants.csv" -NoTypeInformation
        Get-AzResourceGroup | Export-Csv -Path "$outputDir\$($tenant.Name)-resourcegroups.csv" -NoTypeInformation
        
        Write-Host "Gathering VM and Storage Info" -ForegroundColor Cyan
        $skuCache = @{} # This will cache the results of Get-AzComputeResourceSku per location

        foreach ($subscription in $subscriptions) {
            Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Cyan
            try {
                Select-AzSubscription -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null
                
                $environmentReport = @()

                # Pre-load all disks in the subscription into a lookup table for efficiency
                Write-Host "Caching all managed disk information..." -ForegroundColor Cyan
                $allDisksInSub = Get-AzDisk
                $diskLookup = @{}
                $allDisksInSub.ForEach({ $diskLookup[$_.Id] = $_ })

                $vms = Get-AzVM -ErrorAction Stop
                if ($vms.Count -eq 0) {
                    Write-Warning "No VMs found in subscription $($subscription.Name)"
                    continue
                }

                foreach ($vm in $vms) {
                    Write-Host "Processing VM: $($vm.Name)" -ForegroundColor Gray
                    
                    $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status -ErrorAction SilentlyContinue
                    
                    # --- MODERN SKU CACHING LOGIC ---
                    if (-not $skuCache.ContainsKey($vm.Location)) {
                        Write-Host "Querying available SKUs for location $($vm.Location)..." -ForegroundColor DarkCyan
                        # Use the new, recommended cmdlet to get all VM SKUs for the location
                        $resourceSkus = Get-AzComputeResourceSku -Location $vm.Location | Where-Object {$_.ResourceType -eq "virtualMachines" }
                        $skuCache[$vm.Location] = @{}
                        # Process the results into a simple lookup table for performance
                        foreach ($sku in $resourceSkus) {
                            $skuCache[$vm.Location][$sku.Name] = [PSCustomObject]@{
                                NumberOfCores = ($sku.Capabilities | Where-Object { $_.Name -eq 'vCPUs' }).Value
                                MemoryInGB    = ($sku.Capabilities | Where-Object { $_.Name -eq 'MemoryGB' }).Value
                            }
                        }
                    }
                    $vmSizeDetails = $skuCache[$vm.Location][$vm.HardwareProfile.VmSize]

                    # OS Disk Details
                    $osDiskDetails = $diskLookup[$vm.StorageProfile.OsDisk.ManagedDisk.Id]
                    $osDiskTier = if($osDiskDetails) { $osDiskDetails.Sku.Name } else { 'unmanaged' }
                    
                    # Data Disk Details
                    $dataDisksInfo = [System.Collections.Generic.List[string]]::new()
                    $totalDiskSize = $vm.StorageProfile.OsDisk.DiskSizeGB
                    if ($vm.StorageProfile.DataDisks.Count -gt 0) {
                        foreach ($disk in $vm.StorageProfile.DataDisks) {
                            $totalDiskSize += $disk.DiskSizeGB
                            $diskDetails = $diskLookup[$disk.ManagedDisk.Id]
                            $diskTier = if($diskDetails) { $diskDetails.Sku.Name } else { 'unmanaged' }
                            $dataDisksInfo.Add("$($disk.Name) $($disk.DiskSizeGB)GB ($($diskTier))")
                        }
                    }

                    $info = [PSCustomObject]@{
                        'Tenant Id'               = $tenant.Id
                        'Tenant Name'             = $tenant.Name
                        'Subscription Name'        = $subscription.Name
                        'VM ResourceGroup Name'    = $vm.ResourceGroupName
                        'VM Location'              = $vm.Location
                        'VM Name'                  = $vm.Name
                        'VM_Id'                    = $vm.Id
                        'VM Computer Name'         = $vm.OSProfile.ComputerName
                        'VM Size'                  = $vm.HardwareProfile.VmSize
                        'VM Cores'                 = if ($vmSizeDetails) { $vmSizeDetails.NumberOfCores } else { 'N/A' }
                        'VM Memory (GB)'           = if ($vmSizeDetails) { $vmSizeDetails.MemoryInGB } else { 'N/A' }
                        'VM Number Of Disks'       = $vm.StorageProfile.DataDisks.Count + 1
                        'VM Disks Total Size (GB)' = $totalDiskSize
                        'VM OS Name'               = if($vm.StorageProfile.ImageReference.Offer){ "$($vm.StorageProfile.ImageReference.Publisher) $($vm.StorageProfile.ImageReference.Offer) $($vm.StorageProfile.ImageReference.Sku)" } else { $vm.StorageProfile.OsDisk.OsType }
                        'VM OS Version'            = $vm.StorageProfile.ImageReference.Version
                        'VM Hyper-V Generation'    = $vm.HyperVGeneration
                        'VM Running Status'        = $vmStatus.Statuses[-1].DisplayStatus
                        'VM OS Disk Tier'          = $osDiskTier
                        'VM Data Disks (Tier)'     = $dataDisksInfo -join ', '
                    }
                    $environmentReport += $info
                }

                $reportName = "$outputDir\$($tenant.Name)-vm_storage_report_Subscription_$($subscription.Id).csv"
                $environmentReport | Export-CSV $reportName -NoTypeInformation
                Write-Host "VM storage report for subscription $($subscription.Name) exported to $reportName" -ForegroundColor Green
                
            } catch {
                Write-Error "Error processing subscription $($subscription.Name): $_"
            }
        }
        
        Write-Host "Azure VM Assessment completed successfully! Results saved to $outputDir" -ForegroundColor Green
        
    } catch {
        Write-Error "An error occurred during the Azure Assessment: $_"
    }
}

# Execute the function
try {
    AzureAssessment
} catch {
    Write-Error "Error executing the AzureAssessment function: $_"
}
