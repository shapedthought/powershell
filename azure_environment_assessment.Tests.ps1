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
        'Get-AzResource' = '$ResourceId, [switch]$ExpandProperties'
        'Get-AzAksCluster' = ''; 'Get-AzVMwarePrivateCloud' = ''; 'Get-AzVMwareCluster' = '$PrivateCloudName, $ResourceGroupName'
        'Get-AzVMwareGlobalReachConnection' = '$PrivateCloudName, $ResourceGroupName'
        'Get-AzRecoveryServicesVault' = ''; 'Get-AzRecoveryServicesBackupItem' = '$BackupManagementType, $WorkloadType, $VaultId'
        'Get-AzRecoveryServicesBackupProtectionPolicy' = '$VaultId'; 'Get-AzRecoveryServicesBackupJob' = '$VaultId, $From, $To'
        'Get-AzDataProtectionBackupVault' = '$SubscriptionId'; 'Get-AzDataProtectionBackupInstance' = '$ResourceGroupName, $VaultName'
        'Get-AzDataProtectionBackupPolicy' = '$ResourceGroupName, $VaultName'
        'Get-MgContext' = ''; 'Connect-MgGraph' = '$Scopes, $TenantId, [switch]$UseDeviceCode'; 'Get-MgOrganization' = ''
        'Invoke-MgGraphRequest' = '$Method, $Uri'
    }
    foreach ($name in $stubs.Keys) {
        Invoke-Expression ("function global:{0} {{ [CmdletBinding()] param({1}) throw 'stub {0} was called without a mock' }}" -f $name, $stubs[$name])
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
    $snWork = "$hubVnet/subnets/snet-workloads"; $snPe = "$hubVnet/subnets/snet-pe"; $snGw = "$hubVnet/subnets/GatewaySubnet"
    $snMi = "$spokeVnet/subnets/snet-sqlmi"
    $nic01 = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Network/networkInterfaces/nic-vm01"
    $peNic = "/subscriptions/$H/resourceGroups/rg-hub-net/providers/Microsoft.Network/networkInterfaces/pe-stspoke-blob.nic.0001"
    $vm01 = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm01"
    $vm02 = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm02"
    $disk01 = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Compute/disks/vm01-os"
    $diskOrphan = "/subscriptions/$S/resourceGroups/rg-app/providers/Microsoft.Compute/disks/orphan-data"
    $sa = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stspoke01"
    $pe = "/subscriptions/$H/resourceGroups/rg-hub-net/providers/Microsoft.Network/privateEndpoints/pe-stspoke-blob"
    $mi = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.Sql/managedInstances/sqlmi01"
    $cosP = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-periodic"
    $cosG = "/subscriptions/$S/resourceGroups/rg-data/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-gremlin"

    $global:Fake = @{
        H = $H; S = $S; D = $D; T = $T; HubVnet = $hubVnet; Sa = $sa; Mi = $mi; Vm01 = $vm01; Vm02 = $vm02; CosP = $cosP; CosG = $cosG
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
                        [pscustomobject]@{ Id = $snWork; Name = 'snet-workloads'; AddressPrefix = @('10.0.1.0/24'); IpConfigurations = @(@{ Id = "$nic01/ipConfigurations/ipconfig1" }); Delegations = @(); ServiceEndpoints = @(@{ Service = 'Microsoft.Storage' }) }
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
                    )
                })
        }
        Nics = @{
            $H = @([pscustomobject]@{ Id = $peNic; Name = 'pe-stspoke-blob.nic.0001'; IpConfigurations = @(@{ Id = "$peNic/ipConfigurations/privateEndpointIpConfig.1"; Primary = $true; PrivateIpAddress = '10.0.2.4'; PrivateIpAddressVersion = 'IPv4'; Subnet = @{ Id = $snPe } }) })
            $S = @([pscustomobject]@{ Id = $nic01; Name = 'nic-vm01'; IpConfigurations = @(@{ Id = "$nic01/ipConfigurations/ipconfig1"; Primary = $true; PrivateIpAddress = '10.0.1.4'; PrivateIpAddressVersion = 'IPv4'; Subnet = @{ Id = $snWork } }) })
        }
        PEs = @{
            $H = @([pscustomobject]@{ Id = $pe; Name = 'pe-stspoke-blob'; Subnet = @{ Id = $snPe }; NetworkInterfaces = @(@{ Id = $peNic })
                    PrivateLinkServiceConnections = @(@{ PrivateLinkServiceId = $sa; GroupIds = @('blob') }) })
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
                [pscustomobject]@{ Id = $disk01; Name = 'vm01-os'; ResourceGroupName = 'rg-app'; Location = 'westeurope'; Zones = @('1'); ManagedBy = $vm01; DiskState = 'Attached'
                    Sku = @{ Name = 'Premium_LRS' }; DiskSizeGB = 128; Tier = 'P10'; Encryption = @{ Type = 'EncryptionAtRestWithPlatformKey' }; NetworkAccessPolicy = 'AllowAll'; HyperVGeneration = 'V2'; OsType = 'Linux' }
                [pscustomobject]@{ Id = $diskOrphan; Name = 'orphan-data'; ResourceGroupName = 'rg-app'; Location = 'westeurope'; ManagedBy = $null; DiskState = 'Unattached'
                    Sku = @{ Name = 'UltraSSD_LRS' }; DiskSizeGB = 512; Encryption = @{ Type = 'EncryptionAtRestWithCustomerKey' } }
            )
        }
        Storage = @{
            $S = @([pscustomobject]@{ Id = $sa; StorageAccountName = 'stspoke01'; ResourceGroupName = 'rg-data'; PrimaryLocation = 'westeurope'; Kind = 'StorageV2'
                    Sku = @{ Name = 'Standard_ZRS' }; AccessTier = 'Hot'; PublicNetworkAccess = 'Disabled'
                    NetworkRuleSet = @{ DefaultAction = 'Deny'; IpRules = @(); VirtualNetworkRules = @() }; Tags = @{ Environment = 'Prod' } })
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

    function global:Get-FakeForSub { param([hashtable]$Map) $v = $Map[$global:FakeSub]; if ($null -ne $v) { $v } }

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
        Mock Get-AzResource { Get-FakeForSub $global:Fake.Resources }
        Mock Get-AzCosmosDBAccount { $global:Fake.Cosmos[$Name] }
        Mock Get-AzCosmosDBSqlDatabase { [pscustomobject]@{ Name = 'db1' } }
        Mock Get-AzCosmosDBSqlContainer { [pscustomobject]@{ Name = 'c1' }; [pscustomobject]@{ Name = 'c2' } }
        Mock Get-AzCosmosDBGremlinDatabase { [pscustomobject]@{ Name = 'g1' } }
        Mock Get-AzCosmosDBGremlinGraph { [pscustomobject]@{ Name = 'graph1' } }
        Mock Get-AzStorageAccount { Get-FakeForSub $global:Fake.Storage }
        Mock Get-AzStorageBlobServiceProperty { [pscustomobject]@{ IsVersioningEnabled = $true; DeleteRetentionPolicy = @{ Enabled = $true; Days = 7 }; ContainerDeleteRetentionPolicy = @{ Enabled = $false }; ChangeFeed = @{ Enabled = $false }; RestorePolicy = @{ Enabled = $false } } }
        Mock Get-AzStorageFileServiceProperty { [pscustomobject]@{ ShareDeleteRetentionPolicy = @{ Enabled = $true; Days = 14 } } }
        Mock Get-AzRmStorageShare { }
        Mock Get-AzRmStorageContainer { [pscustomobject]@{ Name = 'data' } }
        Mock Get-AzMetricDefinition { [pscustomobject]@{ MetricAvailabilities = @(@{ TimeGrain = [timespan]'00:05:00' }, @{ TimeGrain = [timespan]'01:00:00' }); SupportedAggregationTypes = @('Average', 'Maximum') } }
        Mock Get-AzMetric {
            if ($ResourceId -like '*cosmos-gremlin' -and $MetricName -eq 'DataUsage') { return [pscustomobject]@{ Name = 'DataUsage'; Data = @() } }
            [pscustomobject]@{ Name = $MetricName; Data = @([pscustomobject]@{ Maximum = 5GB; Average = 4GB }, [pscustomobject]@{ Maximum = 10GB; Average = 9GB }) }
        }
    }

    function Invoke-FakeRun {
        param([string]$Path, [switch]$Anonymise, [string]$Salt)
        $global:FakeSub = $null
        $p = @{ AcceptDisclaimer = $true; UseExistingContext = $true; OutputPath = $Path; TagNames = @('Environment') }
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

    It 'places a VM whose NIC sits in a vNet of a different subscription (hub) using the hub backbone' {
        $row = $script:Vms | Where-Object { $_.ResourceKey -eq $global:Fake.Vm01.ToLowerInvariant() }
        $row | Should -Not -BeNullOrEmpty
        $row.SubscriptionId | Should -Be $global:Fake.S
        $row.VNetSubscriptionId | Should -Be $global:Fake.H
        $row.VNetResourceGroup | Should -Be 'rg-hub-net'
        $row.VNetName | Should -Be 'vnet-hub'
        $row.SubnetName | Should -Be 'snet-workloads'
        $row.SubnetPrefix | Should -Be '10.0.1.0/24'
        $row.NetworkAccess | Should -Be 'VNetInjected'
        $row.PrivateIpAddress | Should -Be '10.0.1.4'
        $row.CandidateVeeamProtection | Should -Be 'Veeam Backup for Microsoft Azure: Azure VM'
        $row.Tag_Environment | Should -Be 'Prod'
        $row.vCPUs | Should -Be '2'
        $row.PowerState | Should -Be 'VM running'
        $nic = $script:Att | Where-Object { $_.ResourceKey -eq $row.ResourceKey -and $_.AttachmentType -eq 'Nic' }
        $nic.IsPrimary | Should -Be 'True'
        $nic.VNetSubscriptionId | Should -Be $global:Fake.H
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

    It 'builds subnet capacity, summaries and an environment map that fits ConvertTo-Json -Depth 10' {
        $w = $script:Subnets | Where-Object { $_.SubnetName -eq 'snet-workloads' }
        $w.TotalIPs | Should -Be '256'
        $w.UsedIPs | Should -Be '1'
        $w.AvailableIPs | Should -Be '250'
        $w.CanHostVeeamWorkers | Should -Be 'True'
        $w.HasStorageServiceEndpoint | Should -Be 'True'
        ($script:Subnets | Where-Object { $_.SubnetName -eq 'GatewaySubnet' }).CanHostVeeamWorkers | Should -Be 'False'
        $env = Import-Csv (Join-Path $script:OutA 'environment_summary.csv')
        $hubBucket = $env | Where-Object { $_.SubscriptionId -eq $global:Fake.S -and $_.VNetName -eq 'vnet-hub' }
        $hubBucket.VMs | Should -Be '1'
        $hubBucket.StorageAccounts | Should -Be '1'
        $hubBucket.WorkerCapableSubnets | Should -Be '2'
        ($env | Where-Object { $_.VNetName -eq '(none)' }).CosmosAccounts | Should -Be '2'
        $json = Get-Content (Join-Path $script:OutA 'environment_map.json') -Raw | ConvertFrom-Json
        $res = $json.Subscriptions | ForEach-Object { $_.Regions } | ForEach-Object { $_.VNets } | ForEach-Object { $_.Subnets } | ForEach-Object { $_.Resources }
        @($res | Where-Object { $_.ResourceKey -eq $global:Fake.Sa.ToLowerInvariant() }).Count | Should -Be 1
        ($res | Where-Object { $_.ResourceKey -eq $global:Fake.Vm01.ToLowerInvariant() }).NetworkAccess | Should -Be 'VNetInjected'
        (Import-Csv (Join-Path $script:OutA 'region_summary.csv')).HasWorkerCapableSubnet | Should -Be 'True'
        $other = Import-Csv (Join-Path $script:OutA 'other_resources_summary.csv')
        ($other | Where-Object { $_.ResourceType -eq 'Microsoft.Cache/Redis' }).GapNote | Should -BeLike '*Azure Cache for Redis*'
    }
}

Describe 'Anonymised run (mocked Az)' {
    BeforeAll {
        Set-FakeMocks
        $script:Salt = 'pester-salt-0001'
        $script:OutB = Join-Path $TestDrive 'runB'
        Invoke-FakeRun -Path $script:OutB -Anonymise -Salt $script:Salt
        $script:HubHash = Get-ExpectedHash -Salt $script:Salt -Value 'vnet-hub'
    }

    It 'hashes the same vNet name identically in vms.csv, subnets.csv and network_attachments.csv' {
        $vm = Import-Csv (Join-Path $script:OutB 'vms.csv') | Where-Object { $_.ResourceName -eq (Get-ExpectedHash -Salt $script:Salt -Value 'vm01') }
        $vm.VNetName | Should -Be $script:HubHash
        $vm.ResourceKey | Should -Be (Get-ExpectedHash -Salt $script:Salt -Value $global:Fake.Vm01)
        $vm.SubscriptionId | Should -Be $global:Fake.S
        $vm.VNetSubscriptionId | Should -Be $global:Fake.H
        $vm.Region | Should -Be 'westeurope'
        $vm.NetworkAccess | Should -Be 'VNetInjected'
        (Import-Csv (Join-Path $script:OutB 'subnets.csv') | Where-Object { $_.VNetName -eq $script:HubHash }).Count | Should -Be 3
        @(Import-Csv (Join-Path $script:OutB 'network_attachments.csv') | Where-Object { $_.VNetName -eq $script:HubHash }).Count | Should -Be 2
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
            foreach ($raw in @('vnet-hub', 'snet-workloads', 'stspoke01', 'sqlmi01', 'cosmos-gremlin', 'Contoso-Hub', 'rg-hub-net', '10.0.1.4', 'contoso.onmicrosoft.com', $script:Salt)) {
                $text.Contains($raw) | Should -BeFalse -Because "$($f.Name) must not contain '$raw'"
            }
            $f.Name | Should -Not -Match 'vnet|stspoke|contoso'
        }
        $m = Get-Content (Join-Path $script:OutB 'manifest.json') -Raw | ConvertFrom-Json
        $m.Anonymised | Should -BeTrue
        $m.Parameters.PSObject.Properties.Name | Should -Not -Contain 'AnonymiseSalt'
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
