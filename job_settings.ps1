Add-PSSnapin VeeamPSSnapin

$jobs = Get-VBRComputerBackupJob 

$fullInfo = @()

foreach($job in $jobs) {
    $object = [PSCustomObject]@{
        name= $job.Name
        OSplatform = $job.OSPlatform
        JobEnabled= $job.JobEnabled
        BackupType = $job.BackupType
        BackupRepository = $job.BackupRepository.Name
        ActiveFullOptions = $job.ActiveFullOptions.Enabled
        ActiveSelectedDays = $job.ActiveFullOptions.SelectedDays -join ","
        StorageCompression = $job.StorageOptions.CompressionLevel
        StorageOptimisation = $job.StorageOptions.StorageOptimizationType
        ApplicationProcessingEnabled = $job.ApplicationProcessingEnabled
        SythFullEnabled = $job.SyntheticFullOptions.Enabled
        SythFullDays = $job.SyntheticFullOptions.Days -join ","
        ActiveFullEnabled = $jobs.ActiveFullOptions.Enabled
        ActiveFullDays = $job.ActiveFullOptions.SelectedDays -join ","
        GFSRetentionEnabled = $jobs.GFSRetentionEnabled
    }

    $fullInfo += $object
}


$fullInfo | Export-Csv "./jobSettings.csv" -NoTypeInformation