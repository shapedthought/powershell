Add-PSSnapin VeeamPSSnapin

# Select the text file with the shares listed in \\host\share format
$filePath = Read-Host -Prompt "Enter hostfile path: "

# Select the repository
$repository = Get-VBRBackupRepository | Out-GridView -Title "Cache Repository selection" -PassThru

# Select the proxy
$proxy = Get-VBRNASProxyServer | Out-GridView -Title "File proxies" -PassThru

# Select the backup processing mode
$mode = Read-Host -Prompt "Enter processing mode: VSSSnapshot or Direct (VSS Recommended): "

# Set credentials for the share
$credentials = Get-Credential -Message "Share Credentials"

foreach($share in Get-Content -Path $filePath) {

try {

Add-VBRNASSMBServer -Path $share -AccessCredentials $credentials -SelectedProxyServer $proxy -ProxyMode SelectedProxy -ProcessingMode $mode -CacheRepository $repository -ErrorAction Stop -ErrorVariable $err

} catch {

 $errormessage = $_.Exception.Message 
 $errormessage 

}

}






