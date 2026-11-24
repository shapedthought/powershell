# Pester 5 tests for azure_environment_assessment.ps1. Az cmdlets are stubbed and mocked;
# no Azure connection is made. Generated alongside the script from the prompt at:
# https://github.com/shapedthought/awesome-veeam-prompts/tree/main/VBAz-AzureEnvironmentAssessment
# Run: Invoke-Pester -Path ./azure_environment_assessment.Tests.ps1 -Output Detailed

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Pester 5 tests for azure_environment_assessment.ps1. No Azure connection: every Az / Graph cmdlet
# the script calls is first defined as a stub (Pester can only mock commands that exist) and then mocked.

BeforeAll {
    # ---- Stubs for every external cmdlet the script calls (name -> parameter list) ------------------
    $stubs = [ordered]@{
        'Get-AzContext' = ''; 'Set-AzContext' = '$SubscriptionId, $Context'; 'Connect-AzAccount' = '$TenantId, [switch]$UseDeviceAuthentication'
        'Get-AzSubscription' = '$TenantId'; 'Get-AzTenant' = '$TenantId'; 'Invoke-AzRestMethod' = '$Method, $Path'
        'Get-AzVirtualNetwork' = ''; 'Get-AzPrivateEndpoint' = ''; 'Get-AzNetworkInterface' = ''; 'Get-AzPublicIpAddress' = ''
        'Get-AzVM' = '[switch]$Status'; 'Get-AzDisk' = ''; 'Get-AzComputeResourceSku' = '$Location'
        'Get-AzSqlServer' = ''; 'Get-AzSqlServerFirewallRule' = '$ResourceGroupName, $ServerName'
        'Get-AzSqlServerVirtualNetworkRule' = '$ResourceGroupName, $ServerName'; 'Get-AzSqlServerActiveDirectoryOnlyAuthentication' = '$ResourceGroupName, $ServerName'
        'Get-AzSqlDatabase' = '$ResourceGroupName, $ServerName'; 'Get-AzSqlElasticPool' = '$ResourceGroupName, $ServerName'
        'Get-AzSqlDatabaseBackupShortTermRetentionPolicy' = '$ResourceGroupName, $ServerName, $DatabaseName'
        'Get-AzSqlDatabaseBackupLongTermRetentionPolicy' = '$ResourceGroupName, $ServerName, $DatabaseName'
        'Get-AzSqlInstance' = ''; 'Get-AzSqlInstanceDatabase' = '$InstanceName, $ResourceGroupName'
        'Get-AzCosmosDBAccount' = '$ResourceGroupName, $Name'
        'Get-AzCosmosDBSqlDatabase' = '$ResourceGroupName, $AccountName'; 'Get-AzCosmosDBSqlContainer' = '$ResourceGroupName, $AccountName, $DatabaseName'
        'Get-AzCosmosDBMongoDBDatabase' = '$ResourceGroupName, $AccountName'; 'Get-AzCosmosDBMongoDBCollection' = '$ResourceGroupName, $AccountName, $DatabaseName'
        'Get-AzCosmosDBGremlinDatabase' = '$ResourceGroupName, $AccountName'; 'Get-AzCosmosDBGremlinGraph' = '$ResourceGroupName, $AccountName, $DatabaseName'
        'Get-AzCosmosDBTable' = '$ResourceGroupName, $AccountName'; 'Get-AzCosmosDBCassandraKeyspace' = '$ResourceGroupName, $AccountName'
        'Get-AzCosmosDBCassandraTable' = '$ResourceGroupName, $AccountName, $KeyspaceName'
        'Get-AzStorageAccount' = ''; 'Get-AzStorageBlobServiceProperty' = '$ResourceGroupName, $StorageAccountName'
        'Get-AzStorageFileServiceProperty' = '$ResourceGroupName, $StorageAccountName'
        'Get-AzRmStorageShare' = '$ResourceGroupName, $StorageAccountName, $Name, [switch]$IncludeSnapshot, [switch]$GetShareUsage'
        'Get-AzRmStorageContainer' = '$ResourceGroupName, $StorageAccountName'
        'Get-AzMetric' = '$ResourceId, $MetricName, $StartTime, $EndTime, $TimeGrain, $AggregationType'
        'Get-AzMetricDefinition' = '$ResourceId, $MetricName'
        'Get-AzResource' = '$ResourceId, $ResourceType, [switch]$ExpandProperties'
        'Get-AzAksCluster' = ''; 'Get-AzVMwarePrivateCloud' = ''; 'Get-AzVMwareCluster' = '$PrivateCloudName, $ResourceGroupName'
        'Get-AzVMwareGlobalReachConnection' = '$PrivateCloudName, $ResourceGroupName'
        'Get-AzRecoveryServicesVault' = ''; 'Get-AzRecoveryServicesBackupItem' = '$BackupManagementType, $WorkloadType, $VaultId'
        'Get-AzRecoveryServicesBackupProtectionPolicy' = '$VaultId'; 'Get-AzRecoveryServicesBackupJob' = '$VaultId, $From, $To'
        'Get-AzDataProtectionBackupVault' = '$SubscriptionId'; 'Get-AzDataProtectionBackupInstance' = '$ResourceGroupName, $VaultName'
        'Get-AzDataProtectionBackupPolicy' = '$ResourceGroupName, $VaultName'
        'Get-MgContext' = ''; 'Connect-MgGraph' = '$Scopes, $TenantId, [switch]$UseDeviceCode'; 'Get-MgOrganization' = ''
        'Invoke-MgGraphRequest' = '$Method, $Uri'
    }
    $script:StubNames = @($stubs.Keys)
    foreach ($name in $stubs.Keys) {
        # Script scope (not global): the stubs disappear with the test run and never shadow real Az/Graph cmdlets.
        Invoke-Expression ("function script:{0} {{ [CmdletBinding()] param({1}) throw 'stub {0} was called without a mock' }}" -f $name, $stubs[$name])
    }

    # Dot-source: defines the functions without running the assessment.
    . (Join-Path $PSScriptRoot 'azure_environment_assessment.ps1')
    $script:RetryBaseDelaySeconds = 0

    # ---- Fake estate ----------------------------------------------------------------------------------
    $H = '11111111-1111-1111-1111-111111111111'   # hub
    $S = '22222222-2222-2222-2222-222222222222'   # spoke
    $D = '33333333-3333-3333-3333-333333333333'   # returns 403
    $T = 'aaaaaaaa-0000-0000-0000-000000000001'
    $hubVnet = "/subscriptions/$H/resourceGroups/rg-hub-net/providers/Microsoft.Network/virtualNetworks/vnet-hub"
    $spokeVnet = "/subscriptions/$S/resourceGroups/rg-spoke-net/providers/Microsoft.Network/virtualNetworks/vnet-spoke"
    $snWorkers = "$hubVnet/subnets/snet-workers"; $snPe = "$hubVnet/subnets/snet-pe"; $snGw = "$hubVnet/subnets/GatewaySubnet"
    $snMi = "$spokeVnet/subnets/snet-sqlmi"; $snWork = "$spokeVnet/subnets/snet-workloads"; $snPe2 = "$spokeVnet/subnets/snet-pe2"
    $saFiles = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stfiles01"
    $peNic2 = "/subscriptions/$H/resourceGroups/rg-hub-net/providers/Microsoft.Network/networkInterfaces/pe-kv.nic.0002"
    $pe2 = "/subscriptions/$H/resourceGroups/rg-hub-net/providers/Microsoft.Network/privateEndpoints/pe-kv"
    $kv = "/subscriptions/$H/resourceGroups/rg-hub-sec/providers/Microsoft.KeyVault/vaults/kv-hub"
    $saLocked = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stlocked01"
    $rsv = "/subscriptions/$S/resourceGroups/rg-backup/providers/Microsoft.RecoveryServices/vaults/rsv-spoke"
    $bv = "/subscriptions/$S/resourceGroups/rg-backup/providers/Microsoft.DataProtection/backupVaults/bv-spoke"
    $nic01 = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Network/networkInterfaces/nic-vm01"
    $peNic = "/subscriptions/$H/resourceGroups/rg-hub-net/providers/Microsoft.Network/networkInterfaces/pe-stspoke-blob.nic.0001"
    $vm01 = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm01"
    $vm02 = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm02"
    # vm01-os is deliberately in a different resource group from vm01.
    $disk01 = "/subscriptions/$S/resourceGroups/rg-disks/providers/Microsoft.Compute/disks/vm01-os"
    $diskOrphan = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Compute/disks/orphan-data"
    $sa = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stspoke01"
    $pe = "/subscriptions/$H/resourceGroups/rg-hub-net/providers/Microsoft.Network/privateEndpoints/pe-stspoke-blob"
    $mi = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.Sql/managedInstances/sqlmi01"
    $cosP = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-periodic"
    $cosG = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-gremlin"

    $global:Fake = @{
        SaFiles = $saFiles; SnPe2 = $snPe2
        H = $H; S = $S; D = $D; T = $T; HubVnet = $hubVnet; Sa = $sa; SaLocked = $saLocked; Rsv = $rsv; Bv = $bv; Disk01 = $disk01; DiskOrphan = $diskOrphan
        RsvItem = "$rsv/backupFabrics/Azure/protectionContainers/IaasVMContainer;iaasvmcontainerv2;rg-app;vm01/protectedItems/VM;iaasvmcontainerv2;rg-app;vm01"; Mi = $mi; Vm01 = $vm01; Vm02 = $vm02; CosP = $cosP; CosG = $cosG
        Subs = @(
            [pscustomobject]@{ Id = $H; Name = 'Contoso-Hub'; State = 'Enabled'; TenantId = $T }
            [pscustomobject]@{ Id = $S; Name = 'Contoso-Spoke'; State = 'Enabled'; TenantId = $T }
            [pscustomobject]@{ Id = $D; Name = 'Contoso-Denied'; State = 'Enabled'; TenantId = $T }
        )
        VNets = @{
            $H = @([pscustomobject]@{
                    Id = $hubVnet; Name = 'vnet-hub'; ResourceGroupName = 'rg-hub-net'; Location = 'westeurope'
                    AddressSpace = @{ AddressPrefixes = @('10.0.0.0/16') }; DhcpOptions = @{ DnsServers = @('10.0.0.4') }
                    VirtualNetworkPeerings = @(@{ Name = 'hub-to-spoke'; RemoteVirtualNetwork = @{ Id = $spokeVnet }; PeeringState = 'Connected' })
                    Subnets = @(
                        [pscustomobject]@{ Id = $snWorkers; Name = 'snet-workers'; AddressPrefix = @('10.0.3.0/24'); IpConfigurations = @(); Delegations = @() }
                        [pscustomobject]@{ Id = $snPe; Name = 'snet-pe'; AddressPrefix = @('10.0.2.0/27'); IpConfigurations = @(@{ Id = "$peNic/ipConfigurations/privateEndpointIpConfig.1" }); Delegations = @(); PrivateEndpointNetworkPolicies = 'Disabled' }
                        [pscustomobject]@{ Id = $snGw; Name = 'GatewaySubnet'; AddressPrefix = @('10.0.255.0/27'); IpConfigurations = @(); Delegations = @() }
                    )
                })
            $S = @([pscustomobject]@{
                    Id = $spokeVnet; Name = 'vnet-spoke'; ResourceGroupName = 'rg-spoke-net'; Location = 'westeurope'
                    AddressSpace = @{ AddressPrefixes = @('10.1.0.0/16') }
                    VirtualNetworkPeerings = @(@{ Name = 'spoke-to-hub'; RemoteVirtualNetwork = @{ Id = $hubVnet }; PeeringState = 'Connected' })
                    Subnets = @(
                        [pscustomobject]@{ Id = $snMi; Name = 'snet-sqlmi'; AddressPrefix = @('10.1.0.0/24'); IpConfigurations = @(); Delegations = @(@{ ServiceName = 'Microsoft.Sql/managedInstances' }) }
                        [pscustomobject]@{ Id = $snPe2; Name = 'snet-pe2'; AddressPrefix = @('10.1.2.0/29'); IpConfigurations = @(); Delegations = @() }
                        [pscustomobject]@{ Id = $snWork; Name = 'snet-workloads'; AddressPrefix = @('10.1.1.0/24'); IpConfigurations = @(@{ Id = "$nic01/ipConfigurations/ipconfig1" }); Delegations = @(); ServiceEndpoints = @(@{ Service = 'Microsoft.Storage' }) }
                    )
                })
        }
        Nics = @{
            $H = @(
                [pscustomobject]@{ Id = $peNic; Name = 'pe-stspoke-blob.nic.0001'; IpConfigurations = @(@{ Id = "$peNic/ipConfigurations/privateEndpointIpConfig.1"; Primary = $true; PrivateIpAddress = '10.0.2.4'; PrivateIpAddressVersion = 'IPv4'; Subnet = @{ Id = $snPe } }) }
                [pscustomobject]@{ Id = $peNic2; Name = 'pe-kv.nic.0002'; IpConfigurations = @(@{ Id = "$peNic2/ipConfigurations/privateEndpointIpConfig.1"; Primary = $true; PrivateIpAddress = '10.0.2.5'; PrivateIpAddressVersion = 'IPv4'; Subnet = @{ Id = $snPe } }) }
            )
            # VM NIC: same subscription as the VM, different resource group from its vNet.
            $S = @([pscustomobject]@{ Id = $nic01; Name = 'nic-vm01'; IpConfigurations = @(@{ Id = "$nic01/ipConfigurations/ipconfig1"; Primary = $true; PrivateIpAddress = '10.1.1.4'; PrivateIpAddressVersion = 'IPv4'; Subnet = @{ Id = $snWork } }) })
        }
        PEs = @{
            $H = @([pscustomobject]@{ Id = $pe; Name = 'pe-stspoke-blob'; Subnet = @{ Id = $snPe }; NetworkInterfaces = @(@{ Id = $peNic })
                    PrivateLinkServiceConnections = @(@{ PrivateLinkServiceId = $sa; GroupIds = @('blob'); PrivateLinkServiceConnectionState = @{ Status = 'Approved' } }) }
                # Its NIC IP configuration is NOT listed in the subnet's IpConfigurations (UsedIPs de-dup test).
                [pscustomobject]@{ Id = $pe2; Name = 'pe-kv'; Subnet = @{ Id = $snPe }; NetworkInterfaces = @(@{ Id = $peNic2 })
                    PrivateLinkServiceConnections = @(@{ PrivateLinkServiceId = $kv; GroupIds = @('vault'); PrivateLinkServiceConnectionState = @{ Status = 'Approved' } }) })
            # A manual, still-Pending endpoint to stlocked01: it uses an IP in snet-pe2 but does not make the account reachable.
            $S = @([pscustomobject]@{ Id = "/subscriptions/$S/resourceGroups/rg-spoke-net/providers/Microsoft.Network/privateEndpoints/pe-locked"; Name = 'pe-locked'; Subnet = @{ Id = $snPe2 }; NetworkInterfaces = @()
                    PrivateLinkServiceConnections = @(); ManualPrivateLinkServiceConnections = @(@{ PrivateLinkServiceId = $saLocked; GroupIds = @('blob'); PrivateLinkServiceConnectionState = @{ Status = 'Pending' } }) })
        }
        VMs = @{
            $S = @(
                [pscustomobject]@{ Id = $vm01; Name = 'vm01'; ResourceGroupName = 'rg-app'; Location = 'westeurope'; Zones = @('1'); Tags = @{ Environment = 'Prod' }
                    HardwareProfile = @{ VmSize = 'Standard_D2s_v5' }; NetworkProfile = @{ NetworkInterfaces = @(@{ Id = $nic01; Primary = $true }) }
                    StorageProfile = @{ OsDisk = @{ OsType = 'Linux'; ManagedDisk = @{ Id = $disk01 }; DiskSizeGB = 128 }; DataDisks = @(); ImageReference = @{ Publisher = 'Canonical'; Offer = 'ubuntu-24_04-lts'; Sku = 'server' } }
                    SecurityProfile = @{ SecurityType = 'TrustedLaunch' } }
                [pscustomobject]@{ Id = $vm02; Name = 'vm02'; ResourceGroupName = 'rg-app'; Location = 'westeurope'
                    HardwareProfile = @{ VmSize = 'Standard_D2s_v5' }; NetworkProfile = @{ NetworkInterfaces = @(@{ Id = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Network/networkInterfaces/nic-missing" }) }
                    StorageProfile = @{ OsDisk = @{ OsType = 'Windows'; DiskSizeGB = 64; DiffDiskSettings = @{ Option = 'Local' } }; DataDisks = @() } }
            )
        }
        Disks = @{
            $S = @(
                [pscustomobject]@{ Id = $disk01; Name = 'vm01-os'; ResourceGroupName = 'rg-disks'; Location = 'westeurope'; Zones = @('1'); ManagedBy = $vm01; DiskState = 'Attached'
                    Sku = @{ Name = 'Premium_LRS' }; DiskSizeGB = 128; Tier = 'P10'; Encryption = @{ Type = 'EncryptionAtRestWithPlatformKey' }; NetworkAccessPolicy = 'AllowAll'; HyperVGeneration = 'V2'; OsType = 'Linux' }
                [pscustomobject]@{ Id = $diskOrphan; Name = 'orphan-data'; ResourceGroupName = 'rg-app'; Location = 'westeurope'; ManagedBy = $null; DiskState = 'Unattached'
                    Sku = @{ Name = 'UltraSSD_LRS' }; DiskSizeGB = 512; Encryption = @{ Type = 'EncryptionAtRestWithCustomerKey' } }
            )
        }
        Storage = @{
            $S = @([pscustomobject]@{ Id = $sa; StorageAccountName = 'stspoke01'; ResourceGroupName = 'rg-data'; PrimaryLocation = 'westeurope'; Kind = 'StorageV2'
                    Sku = @{ Name = 'Standard_ZRS' }; AccessTier = 'Hot'; PublicNetworkAccess = 'Disabled'
                    NetworkRuleSet = @{ DefaultAction = 'Deny'; IpRules = @(); VirtualNetworkRules = @() }; Tags = @{ Environment = 'Prod' } }
                [pscustomobject]@{ Id = $saFiles; StorageAccountName = 'stfiles01'; ResourceGroupName = 'rg-data'; PrimaryLocation = 'westeurope'; Kind = 'FileStorage'
                    Sku = @{ Name = 'Premium_LRS' }; PublicNetworkAccess = 'Enabled'; NetworkRuleSet = @{ DefaultAction = 'Allow'; IpRules = @(); VirtualNetworkRules = @() } }
                [pscustomobject]@{ Id = $saLocked; StorageAccountName = 'stlocked01'; ResourceGroupName = 'rg-data'; PrimaryLocation = 'westeurope'; Kind = 'BlockBlobStorage'
                    Sku = @{ Name = 'Premium_LRS' }; PublicNetworkAccess = 'Disabled'; NetworkRuleSet = @{ DefaultAction = 'Allow'; IpRules = @(); VirtualNetworkRules = @() } })
        }
        Instances = @{
            $S = @([pscustomobject]@{ Id = $mi; ManagedInstanceName = 'sqlmi01'; ResourceGroupName = 'rg-data'; Location = 'westeurope'; SubnetId = $snMi
                    Sku = @{ Name = 'GP_Gen5' }; VCores = 8; StorageSizeInGB = 256; LicenseType = 'BasePrice'; PublicDataEndpointEnabled = $false; ProxyOverride = 'Proxy' })
        }
        Resources = @{
            $S = @(
                [pscustomobject]@{ ResourceId = $cosP; Name = 'cosmos-periodic'; ResourceGroupName = 'rg-data'; ResourceType = 'Microsoft.DocumentDB/databaseAccounts'; Location = 'westeurope' }
                [pscustomobject]@{ ResourceId = $cosG; Name = 'cosmos-gremlin'; ResourceGroupName = 'rg-data'; ResourceType = 'Microsoft.DocumentDB/databaseAccounts'; Location = 'westeurope' }
                [pscustomobject]@{ ResourceId = $vm01; Name = 'vm01'; ResourceGroupName = 'rg-app'; ResourceType = 'Microsoft.Compute/virtualMachines'; Location = 'westeurope' }
                [pscustomobject]@{ ResourceId = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.Cache/Redis/redis01"; Name = 'redis01'; ResourceGroupName = 'rg-data'; ResourceType = 'Microsoft.Cache/Redis'; Location = 'westeurope' }
            )
        }
        Cosmos = @{
            'cosmos-periodic' = [pscustomobject]@{ Id = $cosP; Name = 'cosmos-periodic'; Location = 'West Europe'; Kind = 'GlobalDocumentDB'; Capabilities = @()
                BackupPolicy = @{ BackupType = 'Periodic'; BackupIntervalInMinutes = 240; BackupRetentionIntervalInHours = 8 }
                EnableMultipleWriteLocations = $true; PublicNetworkAccess = 'Enabled'; IpRules = @(); VirtualNetworkRules = @()
                WriteLocations = @(@{ LocationName = 'West Europe' }, @{ LocationName = 'North Europe' }); ReadLocations = @(@{ LocationName = 'West Europe' }) }
            'cosmos-gremlin'  = [pscustomobject]@{ Id = $cosG; Name = 'cosmos-gremlin'; Location = 'West Europe'; Kind = 'GlobalDocumentDB'; Capabilities = @(@{ Name = 'EnableGremlin' })
                BackupPolicy = @{ BackupType = 'Continuous'; ContinuousModeTier = 'Continuous7Days' }
                EnableMultipleWriteLocations = $false; PublicNetworkAccess = 'Enabled'; IpRules = @(@{ IpAddressOrRange = '203.0.113.10' }); VirtualNetworkRules = @()
                WriteLocations = @(@{ LocationName = 'West Europe' }); ReadLocations = @(@{ LocationName = 'West Europe' }) }
        }
    }

    function script:Get-FakeForSub { param([hashtable]$Map) $v = $Map[$global:FakeSub]; if ($null -ne $v) { $v } }

    function Set-FakeMocks {
        Mock Test-ModuleAvailable { $true }
        Mock Get-ModuleVersion { '9.9.9' }
        Mock Get-AzContext { [pscustomobject]@{ Account = 'tester@example.test'; Tenant = @{ Id = $global:Fake.T }; Subscription = @{ Id = $global:Fake.H } } }
        Mock Set-AzContext { if ($SubscriptionId) { $global:FakeSub = $SubscriptionId }; [pscustomobject]@{ Name = 'ctx' } }
        Mock Connect-AzAccount { throw 'Connect-AzAccount must not be called with -UseExistingContext' }
        Mock Get-AzSubscription { $global:Fake.Subs }
        Mock Get-AzTenant { [pscustomobject]@{ Id = $global:Fake.T; DefaultDomain = 'contoso.onmicrosoft.com' } }
        Mock Get-AzVirtualNetwork {
            if ($global:FakeSub -eq $global:Fake.D) { throw "Operation returned an invalid status code 'Forbidden' (403). AuthorizationFailed: The client does not have authorization to perform action 'Microsoft.Network/virtualNetworks/read' over scope '/subscriptions/$($global:Fake.D)'." }
            Get-FakeForSub $global:Fake.VNets
        }
        Mock Get-AzNetworkInterface { Get-FakeForSub $global:Fake.Nics }
        Mock Get-AzPrivateEndpoint { Get-FakeForSub $global:Fake.PEs }
        Mock Get-AzPublicIpAddress { }
        Mock Get-AzVM { if ($Status) { foreach ($v in @(Get-FakeForSub $global:Fake.VMs)) { [pscustomobject]@{ Id = $v.Id; PowerState = 'VM running' } } } else { Get-FakeForSub $global:Fake.VMs } }
        Mock Get-AzDisk { Get-FakeForSub $global:Fake.Disks }
        Mock Get-AzComputeResourceSku { [pscustomobject]@{ ResourceType = 'virtualMachines'; Name = 'Standard_D2s_v5'; Capabilities = @(@{ Name = 'vCPUs'; Value = '2' }, @{ Name = 'MemoryGB'; Value = '8' }) } }
        Mock Get-AzSqlServer { }
        Mock Get-AzSqlInstance { Get-FakeForSub $global:Fake.Instances }
        Mock Get-AzSqlInstanceDatabase { [pscustomobject]@{ Id = "$($global:Fake.Mi)/databases/appdb"; Name = 'appdb'; Status = 'Online' }; [pscustomobject]@{ Id = "$($global:Fake.Mi)/databases/master"; Name = 'master' } }
        Mock Get-AzResource { if ($ResourceType) { return }; Get-FakeForSub $global:Fake.Resources }
        Mock Get-AzCosmosDBAccount { $global:Fake.Cosmos[$Name] }
        Mock Get-AzCosmosDBSqlDatabase { [pscustomobject]@{ Name = 'db1' } }
        Mock Get-AzCosmosDBSqlContainer { [pscustomobject]@{ Name = 'c1' }; [pscustomobject]@{ Name = 'c2' } }
        Mock Get-AzCosmosDBGremlinDatabase { [pscustomobject]@{ Name = 'g1' } }
        Mock Get-AzCosmosDBGremlinGraph { [pscustomobject]@{ Name = 'graph1' } }
        Mock Get-AzStorageAccount { Get-FakeForSub $global:Fake.Storage }
        Mock Get-AzStorageBlobServiceProperty {
            if ($StorageAccountName -eq 'stspoke01') { throw "Operation returned an invalid status code 'Forbidden' (403) for storage account 'stspoke01'." }
            [pscustomobject]@{ IsVersioningEnabled = $true; DeleteRetentionPolicy = @{ Enabled = $true; Days = 7 }; ContainerDeleteRetentionPolicy = @{ Enabled = $false }; ChangeFeed = @{ Enabled = $false }; RestorePolicy = @{ Enabled = $false } } }
        Mock Get-AzStorageFileServiceProperty { [pscustomobject]@{ ShareDeleteRetentionPolicy = @{ Enabled = $true; Days = 14 } } }
        Mock Get-AzRmStorageShare { }
        Mock Get-AzRmStorageContainer { [pscustomobject]@{ Name = 'data' } }
        # Existing native backup: a Recovery Services vault protecting vm01 and a Backup vault protecting its OS disk.
        Mock Get-AzRecoveryServicesVault { if ($global:FakeSub -eq $global:Fake.S) { [pscustomobject]@{ ID = $global:Fake.Rsv; Name = 'rsv-spoke'; ResourceGroupName = 'rg-backup'; Location = 'westeurope'; Properties = @{} } } }
        Mock Get-AzRecoveryServicesBackupItem {
            if ($WorkloadType -eq 'AzureVM') {
                [pscustomobject]@{ Id = $global:Fake.RsvItem; Name = 'VM;iaasvmcontainerv2;rg-app;vm01'; SourceResourceId = $global:Fake.Vm01; ProtectionPolicyName = 'DefaultPolicy'
                    ProtectionState = 'Protected'; LastBackupStatus = 'Completed'; LatestRecoveryPoint = [datetime]'2026-11-23T22:00:00Z' }
            }
        }
        Mock Get-AzRecoveryServicesBackupProtectionPolicy { [pscustomobject]@{ Id = "$($global:Fake.Rsv)/backupPolicies/DefaultPolicy"; Name = 'DefaultPolicy'; WorkloadType = 'AzureVM'; SchedulePolicy = @{ ScheduleRunFrequency = 'Daily'; ScheduleRunTimes = @([datetime]'2026-01-01T22:00:00') }; RetentionPolicy = @{ IsDailyScheduleEnabled = $true; DailySchedule = @{ DurationCountInDays = 30 }; IsWeeklyScheduleEnabled = $false; WeeklySchedule = @{ DurationCountInWeeks = 12 } } } }
        Mock Get-AzRecoveryServicesBackupJob { }
        Mock Get-AzDataProtectionBackupVault { if ($SubscriptionId -eq $global:Fake.S) { [pscustomobject]@{ Id = $global:Fake.Bv; Name = 'bv-spoke'; Location = 'westeurope' } } }
        Mock Get-AzDataProtectionBackupPolicy { }
        Mock Get-AzDataProtectionBackupInstance {
            [pscustomobject]@{ Id = "$($global:Fake.Bv)/backupInstances/vm01-os-inst"; Name = 'vm01-os-inst'
                Property = @{ DataSourceInfo = @{ ResourceId = $global:Fake.Disk01; DatasourceType = 'Microsoft.Compute/disks' }; PolicyInfo = @{ PolicyId = "$($global:Fake.Bv)/backupPolicies/disk-daily" }
                    CurrentProtectionState = 'ProtectionConfigured'; ProtectionStatus = @{ Status = 'ProtectionConfigured' } } }
        }
        Mock Get-AzMetricDefinition { [pscustomobject]@{ MetricAvailabilities = @(@{ TimeGrain = [timespan]'00:05:00' }, @{ TimeGrain = [timespan]'01:00:00' }); SupportedAggregationTypes = @('Average', 'Maximum') } }
        Mock Get-AzMetric {
            if ($ResourceId -like '*cosmos-gremlin' -and $MetricName -eq 'DataUsage') { return [pscustomobject]@{ Name = 'DataUsage'; Data = @() } }
            [pscustomobject]@{ Name = $MetricName; Data = @([pscustomobject]@{ Maximum = 5GB; Average = 4GB }, [pscustomobject]@{ Maximum = 10GB; Average = 9GB }) }
        }
    }

    function Invoke-FakeRun {
        param([string]$Path, [switch]$Anonymise, [string]$Salt)
        $global:FakeSub = $null
        $p = @{ AcceptDisclaimer = $true; UseExistingContext = $true; OutputPath = $Path; TagNames = @('Environment'); BackupAssessment = $true }
        if ($Anonymise) { $p.Anonymise = $true; $p.AnonymiseSalt = $Salt }
        Invoke-AzureEnvironmentAssessment @p 6>$null | Out-Null
    }

    function Get-ExpectedHash {
        param([string]$Salt, [string]$Value)
        $h = New-Object System.Security.Cryptography.HMACSHA256 (, [System.Text.Encoding]::UTF8.GetBytes($Salt))
        $b = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant()))
        -join ($b[0..5] | ForEach-Object { $_.ToString('x2') })
    }
}

Describe 'Azure environment assessment (mocked Az)' {
    BeforeAll {
        Set-FakeMocks
        $script:OutA = Join-Path $TestDrive 'runA'
        Invoke-FakeRun -Path $script:OutA
        $script:Vms = Import-Csv (Join-Path $script:OutA 'vms.csv')
        $script:Att = Import-Csv (Join-Path $script:OutA 'network_attachments.csv')
        $script:Errs = Import-Csv (Join-Path $script:OutA 'errors.csv')
        $script:Subnets = Import-Csv (Join-Path $script:OutA 'subnets.csv')
    }

    It 'places a VM whose NIC is in a vNet in a different resource group (same subscription)' {
        $row = $script:Vms | Where-Object { $_.ResourceKey -eq $global:Fake.Vm01.ToLowerInvariant() }
        $row | Should -Not -BeNullOrEmpty
        $row.SubscriptionId | Should -Be $global:Fake.S
        $row.ResourceGroup | Should -Be 'rg-app'
        $row.VNetSubscriptionId | Should -Be $global:Fake.S
        $row.VNetResourceGroup | Should -Be 'rg-spoke-net'
        $row.VNetName | Should -Be 'vnet-spoke'
        $row.SubnetName | Should -Be 'snet-workloads'
        $row.SubnetPrefix | Should -Be '10.1.1.0/24'
        $row.NetworkAccess | Should -Be 'VNetInjected'
        $row.PrivateIpAddress | Should -Be '10.1.1.4'
        $row.Memory_GiB | Should -Be '8'
        $row.CandidateVeeamProtection | Should -Be 'Veeam Backup for Microsoft Azure: Azure VM'
        $row.Tag_Environment | Should -Be 'Prod'
        $row.vCPUs | Should -Be '2'
        $row.PowerState | Should -Be 'VM running'
        $nic = $script:Att | Where-Object { $_.ResourceKey -eq $row.ResourceKey -and $_.AttachmentType -eq 'Nic' }
        $nic.IsPrimary | Should -Be 'True'
        $nic.VNetResourceGroup | Should -Be 'rg-spoke-net'
        (Import-Csv (Join-Path $script:OutA 'vms.csv') | Get-Member -MemberType NoteProperty | Measure-Object).Count | Should -BeGreaterThan 17
        $header = (Get-Content (Join-Path $script:OutA 'vms.csv') -TotalCount 1)
        $header | Should -BeLike '"ResourceKey","TenantId","SubscriptionId","SubscriptionName","ResourceGroup","Region","Zones","ResourceName","ResourceType","NetworkAccess","VNetSubscriptionId","VNetResourceGroup","VNetName","SubnetName","SubnetPrefix","PrivateEndpointCount","CandidateVeeamProtection","Tag_Environment","VmSize"*'
    }

    It 'keeps a row for a VM whose NIC cannot be resolved, with blank network columns and an errors.csv entry' {
        $row = $script:Vms | Where-Object { $_.ResourceKey -eq $global:Fake.Vm02.ToLowerInvariant() }
        $row | Should -Not -BeNullOrEmpty
        $row.VNetName | Should -Be ''
        $row.HasEphemeralOsDisk | Should -Be 'True'
        ($script:Errs | Where-Object { $_.ResourceKey -eq $global:Fake.Vm02.ToLowerInvariant() -and $_.Operation -eq 'ResolveNic' }) | Should -Not -BeNullOrEmpty
    }

    It 'places a storage account by its private endpoint in the hub subscription' {
        $row = Import-Csv (Join-Path $script:OutA 'storage_accounts.csv') | Where-Object { $_.ResourceKey -eq $global:Fake.Sa.ToLowerInvariant() }
        $row.SubscriptionId | Should -Be $global:Fake.S
        $row.NetworkAccess | Should -Be 'PrivateEndpointOnly'
        $row.PrivateEndpointCount | Should -Be '1'
        $row.VNetSubscriptionId | Should -Be $global:Fake.H
        $row.VNetName | Should -Be 'vnet-hub'
        $row.SubnetName | Should -Be 'snet-pe'
        $row.UsedCapacity_GiB | Should -Be '10'
        $row.ContainerCount | Should -Be '1'
        $row.FileShareCount | Should -Be '0'
        $row.CandidateVeeamProtection | Should -Be 'Veeam Backup & Replication: object storage backup (Azure Blob)'
        $a = $script:Att | Where-Object { $_.ResourceKey -eq $row.ResourceKey }
        @($a).Count | Should -Be 1
        $a.AttachmentType | Should -Be 'PrivateEndpoint'
        $a.IsPrimary | Should -Be 'True'
        $a.PrivateEndpointName | Should -Be 'pe-stspoke-blob'
        $a.GroupId | Should -Be 'blob'
        $a.PrivateIpAddress | Should -Be '10.0.2.4'
    }

    It 'places a SQL managed instance on its delegated subnet' {
        $row = Import-Csv (Join-Path $script:OutA 'sql_managed_instances.csv') | Where-Object { $_.ResourceKey -eq $global:Fake.Mi.ToLowerInvariant() }
        $row.NetworkAccess | Should -Be 'VNetInjected'
        $row.VNetName | Should -Be 'vnet-spoke'
        $row.SubnetName | Should -Be 'snet-sqlmi'
        $row.SubnetPrefix | Should -Be '10.1.0.0/24'
        $row.DatabaseCount | Should -Be '1'
        $row.StorageUsed_GiB | Should -Not -BeNullOrEmpty
        ($script:Att | Where-Object { $_.ResourceKey -eq $row.ResourceKey }).AttachmentType | Should -Be 'DelegatedSubnet'
        $db = Import-Csv (Join-Path $script:OutA 'sql_mi_databases.csv')
        @($db).Count | Should -Be 1
        $db.SubnetName | Should -Be 'snet-sqlmi'
        $sn = $script:Subnets | Where-Object { $_.SubnetName -eq 'snet-sqlmi' }
        $sn.CanHostVeeamWorkers | Should -Be 'False'
        $sn.Delegations | Should -Be 'Microsoft.Sql/managedInstances'
    }

    It 'skips a subscription that returns 403 and still completes the run with every CSV header' {
        $m = Get-Content (Join-Path $script:OutA 'manifest.json') -Raw | ConvertFrom-Json
        @($m.SubscriptionsSkipped.SubscriptionId) | Should -Contain $global:Fake.D
        @($m.SubscriptionsProcessed.SubscriptionId) | Should -Contain $global:Fake.H
        @($m.SubscriptionsProcessed.SubscriptionId) | Should -Contain $global:Fake.S
        @($m.SubscriptionsProcessed.SubscriptionId) | Should -Not -Contain $global:Fake.D
        ($script:Errs | Where-Object { $_.SubscriptionId -eq $global:Fake.D }) | Should -Not -BeNullOrEmpty
        foreach ($f in $script:OutputOrder) {
            $p = Join-Path $script:OutA ($f + '.csv')
            $p | Should -Exist
            (Get-Content $p -TotalCount 1) | Should -Not -BeNullOrEmpty
        }
        (Get-Content (Join-Path $script:OutA 'aks_clusters.csv') -TotalCount 1) | Should -BeLike '"ResourceKey",*'
        Join-Path $script:OutA 'environment_map.json' | Should -Exist
    }

    It 'sets both Cosmos DB blockers for periodic + multi-region writes, none for continuous Gremlin' {
        $rows = Import-Csv (Join-Path $script:OutA 'cosmos_accounts.csv')
        $p = $rows | Where-Object { $_.ResourceKey -eq $global:Fake.CosP.ToLowerInvariant() }
        $g = $rows | Where-Object { $_.ResourceKey -eq $global:Fake.CosG.ToLowerInvariant() }
        $p.ApiKind | Should -Be 'NoSQL'
        $p.ProtectionBlockers | Should -Be 'PeriodicBackup;MultiRegionWrites'
        $p.BackupPolicyType | Should -Be 'Periodic'
        $p.RepositoryBackupSupported | Should -Be 'False'
        $p.NetworkAccess | Should -Be 'Public'
        $g.ApiKind | Should -Be 'Gremlin'
        $g.ProtectionBlockers | Should -Be ''
        $g.ContinuousTier | Should -Be 'Continuous7Days'
        $g.CandidateVeeamProtection | Should -Be 'Veeam Backup for Microsoft Azure: Cosmos DB for Apache Gremlin'
        $g.NetworkAccess | Should -Be 'PublicFirewall'
    }

    It 'leaves a metric column blank and logs errors.csv when the metric returns nothing' {
        $rows = Import-Csv (Join-Path $script:OutA 'cosmos_accounts.csv')
        $g = $rows | Where-Object { $_.ResourceKey -eq $global:Fake.CosG.ToLowerInvariant() }
        $p = $rows | Where-Object { $_.ResourceKey -eq $global:Fake.CosP.ToLowerInvariant() }
        $g.DataUsage_GiB | Should -Be ''
        $g.IndexUsage_GiB | Should -Be '10'
        $p.DataUsage_GiB | Should -Be '10'
        $e = $script:Errs | Where-Object { $_.ResourceKey -eq $global:Fake.CosG.ToLowerInvariant() -and $_.Operation -eq 'Get-AzMetric DataUsage' }
        $e | Should -Not -BeNullOrEmpty
        $e.Module | Should -Be 'cosmos'
    }

    It 'reports PublicDisabled for public access disabled with no private endpoint' {
        $row = Import-Csv (Join-Path $script:OutA 'storage_accounts.csv') | Where-Object { $_.ResourceKey -eq $global:Fake.SaLocked.ToLowerInvariant() }
        $row.NetworkAccess | Should -Be 'PublicDisabled'
        $row.VNetName | Should -Be ''
        $row.PrivateEndpointCount | Should -Be '0'
        Resolve-NetworkAccess -PublicNetworkAccess 'Disabled' | Should -Be 'PublicDisabled'
        Resolve-NetworkAccess -PublicNetworkAccess 'Disabled' -PrivateEndpointCount 1 | Should -Be 'PrivateEndpointOnly'
        Resolve-NetworkAccess -PublicNetworkAccess 'Enabled' -DefaultAction 'Deny' | Should -Be 'PublicFirewall'
        Resolve-NetworkAccess -PublicNetworkAccess 'Enabled' -DefaultAction 'Allow' | Should -Be 'Public'
    }

    It 'gives an attached disk its VM network placement but keeps its own resource group, and an unattached disk blank network columns with N/A' {
        $disks = Import-Csv (Join-Path $script:OutA 'disks.csv')
        $att = $disks | Where-Object { $_.ResourceKey -eq $global:Fake.Disk01.ToLowerInvariant() }
        $att.ResourceName | Should -Be 'vm01-os'
        $att.ResourceGroup | Should -Be 'rg-disks'
        $att.SubscriptionId | Should -Be $global:Fake.S
        $att.VNetName | Should -Be 'vnet-spoke'
        $att.SubnetName | Should -Be 'snet-workloads'
        $att.NetworkAccess | Should -Be 'VNetInjected'
        $att.Zones | Should -Be '1'
        $orphan = $disks | Where-Object { $_.ResourceKey -eq $global:Fake.DiskOrphan.ToLowerInvariant() }
        $orphan.Unattached | Should -Be 'True'
        $orphan.NetworkAccess | Should -Be 'N/A'
        $orphan.VNetName | Should -Be ''
        $orphan.SubnetName | Should -Be ''
        $orphan.VNetSubscriptionId | Should -Be ''
    }

    It 'de-duplicates UsedIPs across subnet IP configurations and private endpoint NICs, and counts private endpoints on vNet/subnet rows' {
        $pe = $script:Subnets | Where-Object { $_.SubnetName -eq 'snet-pe' }
        $pe.TotalIPs | Should -Be '32'
        $pe.UsedIPs | Should -Be '2'
        $pe.AvailableIPs | Should -Be '25'
        $pe.PrivateEndpointCount | Should -Be '2'
        $pe.VNetName | Should -Be 'vnet-hub'
        $vn = Import-Csv (Join-Path $script:OutA 'virtual_networks.csv') | Where-Object { $_.ResourceName -eq 'vnet-hub' }
        $vn.PrivateEndpointCount | Should -Be '2'
        $vn.VNetName | Should -Be 'vnet-hub'
        $vn.NetworkAccess | Should -Be 'N/A'
    }

    It 'reports native backup coverage including PlatformBuiltIn, with vault rows carrying blank CandidateVeeamProtection' {
        $cov = Import-Csv (Join-Path $script:OutA 'backup_coverage.csv')
        ($cov | Where-Object { $_.ResourceKey -eq $global:Fake.Vm01.ToLowerInvariant() }).NativeBackup | Should -Be 'RecoveryServicesVault'
        ($cov | Where-Object { $_.ResourceKey -eq $global:Fake.Vm01.ToLowerInvariant() }).PolicyName | Should -Be 'DefaultPolicy'
        ($cov | Where-Object { $_.ResourceKey -eq $global:Fake.Disk01.ToLowerInvariant() }).NativeBackup | Should -Be 'BackupVault'
        ($cov | Where-Object { $_.ResourceKey -eq $global:Fake.CosG.ToLowerInvariant() }).NativeBackup | Should -Be 'PlatformBuiltIn'
        ($cov | Where-Object { $_.ResourceKey -eq $global:Fake.Mi.ToLowerInvariant() }).NativeBackup | Should -Be 'PlatformBuiltIn'
        ($cov | Where-Object { $_.ResourceKey -eq $global:Fake.Sa.ToLowerInvariant() }).NativeBackup | Should -Be 'None'
        $vaults = Import-Csv (Join-Path $script:OutA 'backup_vaults.csv')
        @($vaults).Count | Should -Be 2
        foreach ($v in $vaults) { $v.CandidateVeeamProtection | Should -Be '' }
        $item = Import-Csv (Join-Path $script:OutA 'backup_items.csv') | Where-Object { $_.VaultType -eq 'RecoveryServicesVault' }
        $item.ResourceKey | Should -Be $global:Fake.RsvItem.ToLowerInvariant()
        $item.ResourceGroup | Should -Be 'rg-backup'
        $item.ProtectedResourceKey | Should -Be $global:Fake.Vm01.ToLowerInvariant()
    }

    It 'lists both vault types joined with ";" when both cover a resource' {
        $script:State.Coverage = @{}
        Add-CoverageEntry -Key 'k1' -NativeBackup 'RecoveryServicesVault' -VaultName 'rsv' -PolicyName 'p1'
        Add-CoverageEntry -Key 'k1' -NativeBackup 'BackupVault' -VaultName 'bv' -PolicyName 'p2'
        $script:State.Outputs['vms'] = New-List
        $script:State.Outputs['vms'].Add([pscustomobject]@{ ResourceKey = 'k1' })
        $script:State.Outputs['backup_coverage'] = New-List
        Add-BackupCoverage
        $r = $script:State.Outputs['backup_coverage'][0]
        $r.NativeBackup | Should -Be 'RecoveryServicesVault;BackupVault'
        $r.VaultName | Should -Be 'rsv;bv'
    }

    It 'parses a subnet ID by key so names survive for a subnet outside the backbone' {
        $id = '/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-far/providers/Microsoft.Network/virtualNetworks/vnet-far/subnets/snet-far'
        $p = ConvertFrom-ResourceId $id
        $p.SubscriptionId | Should -Be '99999999-9999-9999-9999-999999999999'
        $p.ResourceGroup | Should -Be 'rg-far'
        $p.Segments['virtualnetworks'] | Should -Be 'vnet-far'
        $p.Segments['subnets'] | Should -Be 'snet-far'
        $rec = [pscustomobject]@{ SubscriptionId = 'x'; Module = 'test'; ResourceId = 'r' }
        $info = Resolve-SubnetInfo -SubnetId $id -Record $rec 6>$null
        $info.VNetName | Should -Be 'vnet-far'
        $info.SubnetName | Should -Be 'snet-far'
        $info.VNetResourceGroup | Should -Be 'rg-far'
    }

    It 'only lets Approved private endpoint connections make a target reachable, but counts every endpoint in its subnet' {
        $row = Import-Csv (Join-Path $script:OutA 'storage_accounts.csv') | Where-Object { $_.ResourceKey -eq $global:Fake.SaLocked.ToLowerInvariant() }
        $row.NetworkAccess | Should -Be 'PublicDisabled'
        $row.PrivateEndpointCount | Should -Be '0'
        $sn = $script:Subnets | Where-Object { $_.SubnetName -eq 'snet-pe2' }
        $sn.PrivateEndpointCount | Should -Be '1'
        $sn.UsedIPs | Should -Be '1'
    }

    It 'gives a FileStorage account row the Azure Files CandidateVeeamProtection' {
        $row = Import-Csv (Join-Path $script:OutA 'storage_accounts.csv') | Where-Object { $_.ResourceKey -eq $global:Fake.SaFiles.ToLowerInvariant() }
        $row.CandidateVeeamProtection | Should -Be 'Veeam Backup for Microsoft Azure: Azure Files'
        $row.Kind | Should -Be 'FileStorage'
    }

    It 'records protection state in backup_coverage.csv and resolves policy retention, skipping disabled schedules' {
        $cov = Import-Csv (Join-Path $script:OutA 'backup_coverage.csv')
        ($cov | Where-Object { $_.ResourceKey -eq $global:Fake.Vm01.ToLowerInvariant() }).ProtectionState | Should -Be 'Protected'
        ($cov | Where-Object { $_.ResourceKey -eq $global:Fake.Disk01.ToLowerInvariant() }).ProtectionState | Should -Be 'ProtectionConfigured'
        $pol = Import-Csv (Join-Path $script:OutA 'backup_policies.csv') | Where-Object { $_.VaultType -eq 'RecoveryServicesVault' }
        $pol.Retention | Should -Be 'D:30'
    }

    It 'reports Unknown instead of None when backup discovery failed for the subscription' {
        $saved = $script:State
        try {
            Initialize-AssessmentState
            $script:State.Outputs['vms'].Add([pscustomobject]@{ ResourceKey = 'k1'; SubscriptionId = 'sub-a' })
            $script:State.Outputs['vms'].Add([pscustomobject]@{ ResourceKey = 'k2'; SubscriptionId = 'sub-b' })
            $script:State.Outputs['cosmos_accounts'].Add([pscustomobject]@{ ResourceKey = 'k3'; SubscriptionId = 'sub-a' })
            Set-CoverageIncomplete 'sub-a'
            Add-BackupCoverage
            $cov = $script:State.Outputs['backup_coverage']
            ($cov | Where-Object { $_.ResourceKey -eq 'k1' }).NativeBackup | Should -Be 'Unknown'
            ($cov | Where-Object { $_.ResourceKey -eq 'k2' }).NativeBackup | Should -Be 'None'
            ($cov | Where-Object { $_.ResourceKey -eq 'k3' }).NativeBackup | Should -Be 'PlatformBuiltIn'
        }
        finally { $script:State = $saved }
    }

    It 'leaves summary capacity blank when no value is known and flags partial capacity' {
        $env = Import-Csv (Join-Path $script:OutA 'environment_summary.csv')
        $none = $env | Where-Object { $_.VNetName -eq '(none)' }
        $none.Cosmos_Data_GiB | Should -Be '10'
        $none.CosmosCapacityComplete | Should -Be 'False'
        ($env | Where-Object { $_.VNetName -eq 'vnet-spoke' }).VmCapacityComplete | Should -Be 'True'
        $c = New-SummaryCounters
        $c['CosmosAccounts'] = 2
        $r = [ordered]@{}
        Add-SummaryCounters -Row $r -Counters $c
        $r['Cosmos_Data_GiB'] | Should -Be ''
        $r['CosmosCapacityComplete'] | Should -BeFalse
        $r['VM_Provisioned_GiB'] | Should -Be 0
        $r['VmCapacityComplete'] | Should -BeTrue
    }

    It 'builds subnet capacity, summaries and an environment map that fits ConvertTo-Json -Depth 10' {
        $w = $script:Subnets | Where-Object { $_.SubnetName -eq 'snet-workloads' }
        $w.VNetName | Should -Be 'vnet-spoke'
        $w.TotalIPs | Should -Be '256'
        $w.UsedIPs | Should -Be '1'
        $w.AvailableIPs | Should -Be '250'
        $w.CanHostVeeamWorkers | Should -Be 'True'
        $w.HasStorageServiceEndpoint | Should -Be 'True'
        ($script:Subnets | Where-Object { $_.SubnetName -eq 'GatewaySubnet' }).CanHostVeeamWorkers | Should -Be 'False'
        $env = Import-Csv (Join-Path $script:OutA 'environment_summary.csv')
        $hubBucket = $env | Where-Object { $_.SubscriptionId -eq $global:Fake.S -and $_.VNetSubscriptionId -eq $global:Fake.H -and $_.VNetName -eq 'vnet-hub' }
        $hubBucket.VNetResourceGroup | Should -Be 'rg-hub-net'
        $hubBucket.StorageAccounts | Should -Be '1'
        $hubBucket.WorkerCapableSubnets | Should -Be '2'
        $spokeBucket = $env | Where-Object { $_.SubscriptionId -eq $global:Fake.S -and $_.VNetName -eq 'vnet-spoke' }
        $spokeBucket.VMs | Should -Be '1'
        $spokeBucket.SqlManagedInstances | Should -Be '1'
        $spokeBucket.WorkerCapableSubnets | Should -Be '1'
        ($env | Where-Object { $_.VNetName -eq '(none)' }).CosmosAccounts | Should -Be '2'
        $env[0].PSObject.Properties.Name | Should -Contain 'AksNodes'
        $env[0].PSObject.Properties.Name | Should -Contain 'AvsHosts'
        $json = Get-Content (Join-Path $script:OutA 'environment_map.json') -Raw | ConvertFrom-Json
        $res = $json.Subscriptions | ForEach-Object { $_.Regions } | ForEach-Object { $_.VNets } | ForEach-Object { $_.Subnets } | ForEach-Object { $_.Resources }
        @($res | Where-Object { $_.ResourceKey -eq $global:Fake.Sa.ToLowerInvariant() }).Count | Should -Be 1
        ($res | Where-Object { $_.ResourceKey -eq $global:Fake.Vm01.ToLowerInvariant() }).NetworkAccess | Should -Be 'VNetInjected'
        (Import-Csv (Join-Path $script:OutA 'region_summary.csv')).HasWorkerCapableSubnet | Should -Be 'True'
        $other = Import-Csv (Join-Path $script:OutA 'other_resources_summary.csv')
        ($other | Where-Object { $_.ResourceType -eq 'Microsoft.Cache/Redis' }).GapNote | Should -BeLike '*Azure Cache for Redis*'
    }
}

Describe 'AKS module (mocked Az)' {
    BeforeAll {
        Set-FakeMocks
        $S = $global:Fake.S
        $script:AksId = "/subscriptions/$S/resourceGroups/rg-aks/providers/Microsoft.ContainerService/managedClusters/aks01"
        $snWork = "/subscriptions/$S/resourceGroups/rg-spoke-net/providers/Microsoft.Network/virtualNetworks/vnet-spoke/subnets/snet-workloads"
        $snMi = "/subscriptions/$S/resourceGroups/rg-spoke-net/providers/Microsoft.Network/virtualNetworks/vnet-spoke/subnets/snet-sqlmi"
        $global:FakeAks = [pscustomobject]@{
            Id = $script:AksId; Name = 'aks01'; ResourceGroupName = 'rg-aks'; Location = 'westeurope'
            CurrentKubernetesVersion = '1.30.5'; NodeResourceGroup = 'MC_rg-aks_aks01'
            NetworkProfile = @{ NetworkPlugin = 'azure' }
            AgentPoolProfiles = @(
                [pscustomobject]@{ Name = 'system'; Mode = 'System'; Count = 3; VmSize = 'Standard_D4s_v5'; OsType = 'Linux'; VnetSubnetID = $snWork }
                [pscustomobject]@{ Name = 'user2'; Mode = 'User'; Count = 2; VmSize = 'Standard_D8s_v5'; OsType = 'Linux'; VnetSubnetID = $snMi }
                [pscustomobject]@{ Name = 'user3'; Mode = 'User'; Count = 1; VmSize = 'Standard_D2s_v5'; OsType = 'Linux' }
            )
        }
        Mock Get-AzAksCluster { if ($global:FakeSub -eq $global:Fake.S) { $global:FakeAks } }
        $script:OutK = Join-Path $TestDrive 'runK'
        $global:FakeSub = $null
        Invoke-AzureEnvironmentAssessment -AcceptDisclaimer -UseExistingContext -OutputPath $script:OutK -Modules vm, vnet, aks 6>$null | Out-Null
        $script:Pools = Import-Csv (Join-Path $script:OutK 'aks_node_pools.csv')
    }

    It 'places each AKS node pool on its own subnet, and inherits the cluster placement only when it has none' {
        $c = Import-Csv (Join-Path $script:OutK 'aks_clusters.csv') | Where-Object { $_.ResourceKey -eq $script:AksId.ToLowerInvariant() }
        $c.NetworkAccess | Should -Be 'VNetInjected'
        $c.SubnetName | Should -Be 'snet-workloads'
        $c.TotalNodeCount | Should -Be '6'
        ($script:Pools | Where-Object { $_.NodePoolName -eq 'system' }).SubnetName | Should -Be 'snet-workloads'
        ($script:Pools | Where-Object { $_.NodePoolName -eq 'user2' }).SubnetName | Should -Be 'snet-sqlmi'
        $u3 = $script:Pools | Where-Object { $_.NodePoolName -eq 'user3' }
        $u3.SubnetName | Should -Be 'snet-workloads'
        $u3.ResourceKey | Should -Be ($script:AksId + '/agentPools/user3').ToLowerInvariant()
    }
}

Describe 'Storage private endpoints are per service (mocked Az)' {
    BeforeAll {
        Set-FakeMocks
        # stspoke01 has public access disabled and only a 'blob' private endpoint (in the hub).
        Mock Get-AzRmStorageShare {
            if ($GetShareUsage) { return [pscustomobject]@{ Name = $Name; ShareUsageBytes = 1073741824 } }
            if ($StorageAccountName -eq 'stspoke01') {
                [pscustomobject]@{ Name = 'share1'; Id = "$($global:Fake.Sa)/fileServices/default/shares/share1"; QuotaGiB = 100; EnabledProtocols = 'SMB' }
            }
        }
        $script:OutP = Join-Path $TestDrive 'runP'
        $global:FakeSub = $null
        Invoke-AzureEnvironmentAssessment -AcceptDisclaimer -UseExistingContext -OutputPath $script:OutP -Modules vnet, files, blob 6>$null | Out-Null
    }

    It 'places a file share only on file endpoints, so a blob-only endpoint leaves it PublicDisabled' {
        $sh = Import-Csv (Join-Path $script:OutP 'file_shares.csv') | Where-Object { $_.ShareName -eq 'share1' }
        $sh | Should -Not -BeNullOrEmpty
        $sh.NetworkAccess | Should -Be 'PublicDisabled'
        $sh.PrivateEndpointCount | Should -Be '0'
        $sh.VNetName | Should -Be ''
        $sa = Import-Csv (Join-Path $script:OutP 'storage_accounts.csv') | Where-Object { $_.ResourceKey -eq $global:Fake.Sa.ToLowerInvariant() }
        $sa.NetworkAccess | Should -Be 'PrivateEndpointOnly'
        $sa.SubnetName | Should -Be 'snet-pe'
    }
}

Describe 'Anonymised run (mocked Az)' {
    BeforeAll {
        Set-FakeMocks
        $script:Salt = 'pester-salt-0001'
        $script:OutB = Join-Path $TestDrive 'runB'
        Invoke-FakeRun -Path $script:OutB -Anonymise -Salt $script:Salt
        $script:SpokeHash = Get-ExpectedHash -Salt $script:Salt -Value 'vnet-spoke'
    }

    It 'hashes the same vNet name identically in vms.csv, subnets.csv and network_attachments.csv' {
        $vm = Import-Csv (Join-Path $script:OutB 'vms.csv') | Where-Object { $_.ResourceName -eq (Get-ExpectedHash -Salt $script:Salt -Value 'vm01') }
        $vm.VNetName | Should -Be $script:SpokeHash
        $vm.ResourceKey | Should -Be (Get-ExpectedHash -Salt $script:Salt -Value $global:Fake.Vm01)
        $vm.SubscriptionId | Should -Be $global:Fake.S
        $vm.VNetSubscriptionId | Should -Be $global:Fake.S
        $vm.Region | Should -Be 'westeurope'
        $vm.NetworkAccess | Should -Be 'VNetInjected'
        @(Import-Csv (Join-Path $script:OutB 'subnets.csv') | Where-Object { $_.VNetName -eq $script:SpokeHash }).Count | Should -Be 3
        @(Import-Csv (Join-Path $script:OutB 'network_attachments.csv') | Where-Object { $_.VNetName -eq $script:SpokeHash }).Count | Should -Be 2
        $sn = Import-Csv (Join-Path $script:OutB 'subnets.csv') | Where-Object { $_.SubnetName -eq (Get-ExpectedHash -Salt $script:Salt -Value 'snet-workloads') }
        $sn.SubnetPrefix | Should -Match '^[0-9a-f]{12}/24$'
        $sn.AvailableIPs | Should -Be '250'
        $sn.CanHostVeeamWorkers | Should -Be 'True'
    }

    It 'writes no raw resource ID, raw name or the salt to any output file' {
        $files = Get-ChildItem -Path $script:OutB -File
        $files.Count | Should -BeGreaterThan 20
        foreach ($f in $files) {
            $text = Get-Content $f.FullName -Raw
            if (-not $text) { continue }
            $text | Should -Not -Match '(?i)/subscriptions/' -Because $f.Name
            $text | Should -Not -Match '(?i)/providers/' -Because $f.Name
            foreach ($raw in @('vnet-hub', 'vnet-spoke', 'snet-workloads', 'stspoke01', 'sqlmi01', 'cosmos-gremlin', 'Contoso-Hub', 'rg-hub-net', '10.1.1.4', 'contoso.onmicrosoft.com', 'rsv-spoke', 'DefaultPolicy', $script:Salt)) {
                $text.Contains($raw) | Should -BeFalse -Because "$($f.Name) must not contain '$raw'"
            }
            $f.Name | Should -Not -Match 'vnet|stspoke|contoso'
        }
        $m = Get-Content (Join-Path $script:OutB 'manifest.json') -Raw | ConvertFrom-Json
        $m.Anonymised | Should -BeTrue
        $m.Parameters.PSObject.Properties.Name | Should -Not -Contain 'AnonymiseSalt'
    }

    It 'prints no raw names, IDs or addresses to the console when anonymising' {
        $global:FakeSub = $null
        $console = Invoke-AzureEnvironmentAssessment -AcceptDisclaimer -UseExistingContext -OutputPath (Join-Path $TestDrive 'runB2') -TagNames Environment -BackupAssessment -Anonymise -AnonymiseSalt $script:Salt 6>&1 | Out-String
        $console | Should -Not -BeNullOrEmpty
        foreach ($raw in @('/subscriptions/', 'vnet-hub', 'vnet-spoke', 'stspoke01', 'sqlmi01', 'cosmos-gremlin', 'Contoso-Hub', 'rg-hub-net', '10.1.1.4', 'runB2')) {
            $console.Contains($raw) | Should -BeFalse -Because "console must not show '$raw'"
        }
    }

    It 'replaces errors.csv messages with allowlisted diagnostics (status and error code only) when anonymising' {
        $e = Import-Csv (Join-Path $script:OutB 'errors.csv') | Where-Object { $_.Operation -eq 'Get-AzStorageBlobServiceProperty' }
        $e | Should -Not -BeNullOrEmpty
        $e.Message | Should -BeLike '*HTTP 403*'
        $e.Message | Should -BeLike '*Forbidden*'
        $e.Message | Should -Not -BeLike '*stspoke01*'
        $e.Message | Should -Not -BeLike ("*" + (Get-ExpectedHash -Salt $script:Salt -Value 'stspoke01') + "*")
        $m = Get-Content (Join-Path $script:OutB 'manifest.json') -Raw | ConvertFrom-Json
        $m.Parameters.OutputPath | Should -Not -BeLike '*runB*'
        $e.ResourceKey | Should -Be (Get-ExpectedHash -Salt $script:Salt -Value $global:Fake.Sa)
    }
}

Describe 'Incomplete private endpoint listing (mocked Az)' {
    BeforeAll {
        Set-FakeMocks
        Mock Get-AzPrivateEndpoint { if ($global:FakeSub -eq $global:Fake.H) { throw 'listing failed' }; Get-FakeForSub $global:Fake.PEs }
        $script:OutU = Join-Path $TestDrive 'runU'
        $global:FakeSub = $null
        Invoke-AzureEnvironmentAssessment -AcceptDisclaimer -UseExistingContext -OutputPath $script:OutU -Modules vnet, blob 6>$null | Out-Null
    }

    It 'reports Unknown with a blank PrivateEndpointCount instead of a confident value, and records it in the manifest' {
        $rows = Import-Csv (Join-Path $script:OutU 'storage_accounts.csv')
        $sa = $rows | Where-Object { $_.ResourceKey -eq $global:Fake.Sa.ToLowerInvariant() }
        $sa.NetworkAccess | Should -Be 'Unknown'
        $sa.PrivateEndpointCount | Should -Be ''
        ($rows | Where-Object { $_.ResourceKey -eq $global:Fake.SaLocked.ToLowerInvariant() }).NetworkAccess | Should -Be 'Unknown'
        $m = Get-Content (Join-Path $script:OutU 'manifest.json') -Raw | ConvertFrom-Json
        $m.BackboneComplete | Should -BeFalse
        @($m.PrivateEndpointListingFailed) | Should -Contain $global:Fake.H
    }
}

Describe 'Entra and AVS modules (mocked Az and Graph)' {
    BeforeAll {
        Set-FakeMocks
        $global:MgConnected = $false
        Mock Get-MgContext { if ($global:MgConnected) { [pscustomobject]@{ TenantId = $global:Fake.T } } else { [pscustomobject]@{ TenantId = 'bbbbbbbb-0000-0000-0000-000000000002' } } }
        Mock Connect-MgGraph { $global:MgConnected = $true }
        Mock Get-MgOrganization { [pscustomobject]@{ VerifiedDomains = @(@{ Name = 'contoso.onmicrosoft.com'; IsDefault = $true }) } }
        Mock Invoke-MgGraphRequest {
            if ($Uri -like '*page=2') { return @{ value = @(@{ id = 3 }) } }
            if ($Uri -like '*/users?*') { return @{ value = @(@{ id = 1 }, @{ id = 2 }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?page=2' } }
            @{ value = @(@{ id = 1 }) }
        }
        $pc1 = "/subscriptions/$($global:Fake.S)/resourceGroups/rg-avs/providers/Microsoft.AVS/privateClouds/avs01"
        $pc2 = "/subscriptions/$($global:Fake.S)/resourceGroups/rg-avs/providers/Microsoft.AVS/privateClouds/avs02"
        Mock Get-AzVMwarePrivateCloud {
            if ($global:FakeSub -eq $global:Fake.S) {
                [pscustomobject]@{ Id = $pc1; Name = 'avs01'; ResourceGroupName = 'rg-avs'; Location = 'westeurope'; SkuName = 'av36'; ManagementClusterSize = 3; ManagementClusterId = 1 }
                [pscustomobject]@{ Id = $pc2; Name = 'avs02'; ResourceGroupName = 'rg-avs'; Location = 'westeurope'; SkuName = 'av36'; ManagementClusterSize = 3; ManagementClusterId = 1 }
            }
        }
        # avs01's listing includes the management cluster (ClusterId 1); avs02's listing is empty.
        Mock Get-AzVMwareCluster { if ($PrivateCloudName -eq 'avs01') { [pscustomobject]@{ Name = 'Cluster-1'; ClusterId = 1; ClusterSize = 3 }; [pscustomobject]@{ Name = 'Cluster-2'; ClusterId = 2; ClusterSize = 4 } } }
        Mock Get-AzVMwareGlobalReachConnection { }
        $script:OutE = Join-Path $TestDrive 'runE'
        $global:FakeSub = $null
        Invoke-AzureEnvironmentAssessment -AcceptDisclaimer -UseExistingContext -OutputPath $script:OutE -Modules vnet, avs, entra 6>$null | Out-Null
    }

    It 'reconnects Graph when the existing context is for another tenant, and follows @odata.nextLink' {
        Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope Describe -ParameterFilter { $TenantId -eq $global:Fake.T }
        $e = Import-Csv (Join-Path $script:OutE 'entra_tenant.csv')
        $e.TenantId | Should -Be $global:Fake.T
        $e.Users | Should -Be '3'
        $e.Groups | Should -Be '1'
    }

    It 'refuses to label another tenant''s Graph data with the assessed tenant' {
        Mock Get-MgContext { [pscustomobject]@{ TenantId = 'bbbbbbbb-0000-0000-0000-000000000002' } }
        Mock Connect-MgGraph { }
        { Get-EntraInventory -TenantId $global:Fake.T 6>$null } | Should -Throw '*not for the assessed tenant*'
    }

    It 'does not double-count the AVS management cluster, and falls back to its size when the listing is empty' {
        $rows = Import-Csv (Join-Path $script:OutE 'avs_private_clouds.csv')
        $a1 = $rows | Where-Object { $_.ResourceName -eq 'avs01' }
        $a1.TotalHosts | Should -Be '7'
        $a1.HostCountPerCluster | Should -Be '3;4'
        ($rows | Where-Object { $_.ResourceName -eq 'avs02' }).TotalHosts | Should -Be '3'
    }
}

Describe 'Run-level failures (mocked Az)' {
    BeforeEach { Set-FakeMocks; $global:FakeSub = $null }

    It 'exits non-zero but still writes diagnostics when subscription listing fails, without raw text on the console when anonymising' {
        Mock Get-AzSubscription { throw "Listing failed for '/subscriptions/$($global:Fake.H)/resourceGroups/rg-secret' and account 'stsecret01' (403) AuthorizationFailed" }
        $out = Join-Path $TestDrive 'runF1'
        $console = Invoke-AzureEnvironmentAssessment -AcceptDisclaimer -UseExistingContext -OutputPath $out -Modules vnet -Anonymise -AnonymiseSalt 's1' 6>&1 | Out-String
        $script:ExitCode | Should -Be 1
        $err = Import-Csv (Join-Path $out 'errors.csv') | Where-Object { $_.Operation -eq 'Run' }
        $err | Should -Not -BeNullOrEmpty
        $err.Message | Should -Not -BeLike '*rg-secret*'
        $console | Should -Not -BeLike '*rg-secret*'
        $console | Should -Not -BeLike '*stsecret01*'
        $console | Should -Not -BeLike '*/subscriptions/*'
        $console | Should -BeLike '*AuthorizationFailed*'
    }

    It 'fails the run (non-zero exit) when a CSV write fails' {
        Mock Export-Csv { throw 'disk full' }
        Invoke-AzureEnvironmentAssessment -AcceptDisclaimer -UseExistingContext -OutputPath (Join-Path $TestDrive 'runF2') -Modules vnet 6>$null | Out-Null
        $script:ExitCode | Should -Be 1
    }

    It 'writes no data and exits non-zero when anonymisation fails' {
        Mock ConvertTo-MaskedRow { throw 'mask failure' }
        $out = Join-Path $TestDrive 'runF3'
        Invoke-AzureEnvironmentAssessment -AcceptDisclaimer -UseExistingContext -OutputPath $out -Modules vnet -Anonymise -AnonymiseSalt 's1' 6>$null | Out-Null
        $script:ExitCode | Should -Be 1
        @(Get-ChildItem -Path $out -File).Name | Should -Be @('manifest.json')
        (Get-Content (Join-Path $out 'manifest.json') -Raw | ConvertFrom-Json).Status | Should -BeLike 'Failed*'
    }
}

Describe 'Test hygiene' {
    It 'keeps the Az/Graph stubs out of the global scope so they never shadow real cmdlets' {
        foreach ($n in $script:StubNames) { Test-Path ("function:global:" + $n) | Should -BeFalse -Because $n }
        Test-Path 'function:global:Get-FakeForSub' | Should -BeFalse
    }
}

Describe 'Invoke-WithRetry' {
    BeforeAll { $script:RetryBaseDelaySeconds = 0 }
    It 'retries HTTP 429 and succeeds' {
        $script:calls = 0
        $r = Invoke-WithRetry -ScriptBlock { $script:calls++; if ($script:calls -lt 3) { throw 'Response status code 429 (TooManyRequests)' }; 'ok' } 6>$null
        $r | Should -Be 'ok'
        $script:calls | Should -Be 3
    }
    It 'does not retry HTTP 403' {
        $script:calls = 0
        { Invoke-WithRetry -ScriptBlock { $script:calls++; throw 'Forbidden (403) AuthorizationFailed' } } | Should -Throw
        $script:calls | Should -Be 1
    }
    It 'gives up after 4 retries on 5xx' {
        $script:calls = 0
        { Invoke-WithRetry -ScriptBlock { $script:calls++; throw 'ServiceUnavailable (503)' } 6>$null } | Should -Throw
        $script:calls | Should -Be 5
    }
}

AfterAll {
    # Leave the session clean: no fake-estate globals survive the run (stubs are script-scoped).
    foreach ($v in @('Fake', 'FakeSub', 'FakeAks', 'MgConnected')) { Remove-Variable -Name $v -Scope Global -ErrorAction SilentlyContinue }
}
