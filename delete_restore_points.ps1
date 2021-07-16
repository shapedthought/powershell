# Example script to delete individual restore points from a Veeam Backup.
# The script uses Out-GridView to provide a method of picking objects from a GUI.

# Remove next line for v11
Add-PSSnapin VeeamPSSnapin

# Select Backup from the list
$backup = Get-VBRBackup | Out-GridView -Title "Select Backup" -PassThru

# Select VM from the next list
$vm = Get-VBRRestorePoint -Backup $backup | Out-GridView -Title "Select VM" -PassThru

# Confirm deletion
Remove-VBRRestorePoint -Oib $vm
