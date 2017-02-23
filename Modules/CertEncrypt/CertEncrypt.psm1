Function Get-CertEncryptedString{
<#
 .Synopsis
  Encrypts string using certificate in protected storage

 .Description
  Encrypts string using asymmentric algorythm. Requires certificate in user or machine windows certificate storage

 .Parameter SourceString
  String to be encrypted

 .Parameter CertThumbprint
  Thumbprint of certificate to use for encryption.

 .Parameter UseMachineStorage
  Use certificate in machine storage instead of user storage.

 .Parameter Path
  Path to certificate file to use instead of storage.

  .Example
   # Encrypt string 'Pa$$w0rd'.
   Get-CertEncryptedString -SourceString 'Pa$$w0rd' -CertThumbprint '6E25D30471D2E0CA826593D5A633C4DBA8514881'

  .Output
   Returns enrypted string

#>
param(
[Parameter(Position=0,
    Mandatory=$True,
    ValueFromPipeline=$True)][string]$SourceString,

[Parameter(Position=1,
    Mandatory=$True,
    ValueFromPipeline=$True,
    ParameterSetName='ProtectedStorage')][string]$CertThumbprint,

[Parameter(ParameterSetName='ProtectedStorage')][switch]$UseMachineStorage,

[Parameter(ParameterSetName='File')][string]$Path
)
if ($UseMachineStorage){
    $store = "Cert:\LocalMachine\My"
    }
else {
    $store = "Cert:\CurrentUser\My"
    }
if ($path) {
	$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
	$cert.Import($Path)
} else {
	$cert = Get-ChildItem $store | Where-Object {$_.thumbprint -eq $CertThumbprint}
}
$EncodedString = [system.text.encoding]::UTF8.GetBytes($SourceString)
$EncryptedBytes = $Cert.PublicKey.Key.Encrypt($EncodedString, $true)
[System.Convert]::ToBase64String($EncryptedBytes)
}


Function Get-CertDecryptedString{
<#
 .Synopsis
  Decrypts string using certificate in protected storage

 .Description
  Decrypts string using asymmentric algorythm. Requires certificate in user or machine windows certificate storage

 .Parameter SourceString
  Encrypted String to be decrypted

 .Parameter CertThumbprint
  Thumbprint of certificate to use for decryption.

 .Parameter UseMachineStorage
  Use certificate in machine storage instead of user storage.

  .Example
   # Decrypt string.
   $EncPw = 'dvSbHHCu1vHgM5DaDuGkJ2ax4v9dDmVNEuS3XAzXxoz1BJZ6P5rSrosJQIsTGN5SvVSLGZQDSeS9K3V656cN6Ip/rG2Sx+hWmfRi7WcLpASYVdPqpBfGwBm+JjtiDuVlwUJBTp2/lwev2UtE194SBtHzG/+Bn/O5FWL8yKWE1gVusOa5oiSb7kKNCGMblcV3PvGkOQ3/heUImIV1kjwqWhALh2xDTtKa6lu9BwxkPq/peXLcVpCyS3YRQ7BjkHKz4VzWY5ZXdx2mqXS5+0a8ccJUVEkPaWfUT9tzp7F1dhC4spMbyN2U2l0joE2gAui+93bXS6VrC2aARk6lSGYYnA=='
   Get-CertDecryptedString -SourceString $EncPw -CertThumbprint '6E25D30471D2E0CA826593D5A633C4DBA8514881'

  .Output
   Returns decrypted string
#>
param(
[Parameter(Position=0,
    Mandatory=$True,
    ValueFromPipeline=$True)]
[string]$SourceString,
[string]$CertThumbprint,
[switch]$UseMachineStorage,
[switch]$AsSecureString
)
if ($UseMachineStorage){
    $store = "Cert:\LocalMachine\My"
    }
else {
    $store = "Cert:\CurrentUser\My"
    }
$cert = Get-ChildItem $store | Where-Object {$_.thumbprint -eq $CertThumbprint}
$EncryptedBytes = [System.Convert]::FromBase64String($SourceString)
$DecryptedBytes = $Cert.PrivateKey.Decrypt($EncryptedBytes, $true)
$DecryptedString = [system.text.encoding]::UTF8.GetString($DecryptedBytes)
if ($AsSecureString){
    ConvertTo-SecureString -String $DecryptedString -AsPlainText -Force
    }
else {
    $DecryptedString
    }
}


Export-ModuleMember Get-CertEncryptedString
Export-ModuleMember Get-CertDecryptedString