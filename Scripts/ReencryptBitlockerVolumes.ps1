$DesiredEncryptionMethod = "XtsAes256"

#Disable BitLocker on all volumes
$MountPointsToReEncrypt = Get-BitLockerVolume | where-object {$_.EncryptionMethod -ne $DesiredEncryptionMethod} | Select-object -ExpandProperty MountPoint
$MountPointsToReEncrypt | ForEach-Object {Disable-BitLocker -MountPoint $_} 
#Recheck decryption status every 30 seconds until decryption complete

Do {
    $AllDecrypted = $true
    foreach ($MountPoint in $MountPointsToReEncrypt){
        if ((Get-BitLockerVolume -MountPoint $MountPoint).VolumeStatus -ne "FullyDecrypted") {$AllDecrypted = $false}
        }
    if (-not $AllDecrypted) {Start-Sleep -s 30}
}
Until ($AllDecrypted)

#Enable BitLocker on all volumes
Enable-BitLocker -MountPoint $MountPointsToReEncrypt -EncryptionMethod $DesiredEncryptionMethod -UsedSpaceOnly -SkipHardwareTest -RecoveryPasswordProtector

#Backup Recovery Key for all Volumes
Get-BitLockerVolume | Foreach-object{
    $KeyProtectorId = $_.KeyProtector | where-object {$_.KeyProtectorType -eq 'RecoveryPassword'} | Select-Object -ExpandProperty KeyProtectorId
    if ($KeyProtectorId) {BackupToAAD-BitLockerKeyProtector -MountPoint $_.MountPoint -KeyProtectorId $KeyProtectorId}
    }
