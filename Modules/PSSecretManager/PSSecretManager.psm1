$global:PSSMDatabasePathPreference = $(Join-path $(Split-path $profile -parent) 'PSSecretsManager.json')

Function Get-CertEncryptedString {
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
        [Parameter(Position = 0,
            Mandatory = $True,
            ValueFromPipeline = $True)][string]$SourceString,

        [Parameter(Position = 1,
            Mandatory = $True,
            ValueFromPipeline = $True,
            ParameterSetName = 'ProtectedStorage')][string]$CertThumbprint,

        [Parameter(ParameterSetName = 'ProtectedStorage')][switch]$UseMachineStorage,

        [Parameter(ParameterSetName = 'File')][string]$Path
    )
    if ($UseMachineStorage) {
        $store = "Cert:\LocalMachine\My"
    }
    else {
        $store = "Cert:\CurrentUser\My"
    }
    if ($path) {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $cert.Import($Path)
    }
    else {
        $cert = Get-ChildItem $store | Where-Object {$_.thumbprint -eq $CertThumbprint}
    }
    $EncodedString = [system.text.encoding]::UTF8.GetBytes($SourceString)
    $EncryptedBytes = $Cert.PublicKey.Key.Encrypt($EncodedString, $true)
    [System.Convert]::ToBase64String($EncryptedBytes)
}

Function Get-CertDecryptedString {
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
        [Parameter(Position = 0,
            Mandatory = $True,
            ValueFromPipeline = $True)]
        [string]$SourceString,
        [string]$CertThumbprint,
        [switch]$UseMachineStorage,
        [switch]$AsSecureString
    )
    if ($UseMachineStorage) {
        $store = "Cert:\LocalMachine\My"
    }
    else {
        $store = "Cert:\CurrentUser\My"
    }
    $cert = Get-ChildItem $store | Where-Object {$_.thumbprint -eq $CertThumbprint}
    $EncryptedBytes = [System.Convert]::FromBase64String($SourceString)
    $DecryptedBytes = $Cert.PrivateKey.Decrypt($EncryptedBytes, $true)
    $DecryptedString = [system.text.encoding]::UTF8.GetString($DecryptedBytes)
    if ($AsSecureString) {
        ConvertTo-SecureString -String $DecryptedString -AsPlainText -Force
    }
    else {
        $DecryptedString
    }
}

Function Import-PSSMDatabase {
    param(
        $Path = $PSSMDatabasePathPreference
    )
    $DatabaseFields = @('SecretName', 'UserName', 'SecurePass', 'EncryptedKey', 'CertThumbprint', 'UseMachineStorage', 'Description')
    $ImportantFields = @('SecretName', 'UserName', 'SecurePass', 'EncryptedKey', 'CertThumbprint')
    $JSON = $(Get-Content $Path) -join ""
    $Records = ConvertFrom-Json $JSON
    $Database = @{}
    foreach ($record in $records) {
        $Check = $true
        $record = $record | Select-Object $DatabaseFields
        $fields = $record | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
        foreach ($Ifield in $ImportantFields) {
            if ($fields -notcontains $Ifield) {
                Write-Debug "Field $Ifield not present in DBRecord"
                $Check = $false
            }
        }
        if ($Check) {
            $Database[$record.SecretName] = $record
        }
    }
    return $Database
}

Function Set-PSSMCurrentDatabase {
    param(
        $Path = $PSSMDatabasePathPreference
    )
    if (test-path $Path) {
        $global:PSSMCurrentDatabase = Import-PSSMDatabase -Path $Path
    }
    Else {
        $global:PSSMCurrentDatabase = @{}
    }
    $global:PSSMCurrentDatabasePath = $Path
}

Function Export-PSSMDatabase {
    param(
        [string]$Path = $PSSMDatabasePathPreference,
        [hashtable]$PSSMDatabase = $PSSMCurrentDatabase,
        [switch]$Force
    )
    $JSON = $PSSMDatabase.Values | ConvertTo-Json
    $JSON | Set-Content -Path $Path -Force:$Force
}

Function New-PSSMSecret {
    param(
        [Parameter (Mandatory = $true)][string]$SecretName,
        [Parameter (Mandatory = $true, ParameterSetName = 'Text')][string]$UserName,
        [Parameter (Mandatory = $true, ParameterSetName = 'Text')][SecureString]$Password,
        [Parameter (Mandatory = $true, ParameterSetName = 'PSCredential')][PSCredential]$Credential,
        [Parameter (Mandatory = $true)][string]$CertThumbprint,
        [switch]$UseMachineStorage,
        [string]$Description
    )
    if ($PsCmdlet.ParameterSetName -eq "Text") {
        $Credential = New-Object System.Management.Automation.PSCredential ($UserName, $Password)
    }
    $rng = new-object Security.Cryptography.RNGCryptoServiceProvider
    $key = New-Object Byte[] 24
    $rng.GetBytes($key, 0, 24)
    $Base64Key = [convert]::ToBase64String($key)
    $SecurePass = $Credential.Password | ConvertFrom-SecureString -Key $key
    $EncryptedKey = Get-CertEncryptedString -SourceString $Base64Key -CertThumbprint $CertThumbprint -UseMachineStorage:$UseMachineStorage
    $key = $null
    $Base64Key = $null
    $rng.Dispose()
    [PSCustomObject]@{
        SecretName = $SecretName;
        UserName = $Credential.UserName;
        SecurePass = $SecurePass;
        EncryptedKey = $EncryptedKey;
        CertThumbprint = $CertThumbprint;
        UseMachineStorage = [bool]$UseMachineStorage;
        Description = $Description
    }
}

Function Add-PSSMSecret {
    param(
        [Parameter (Mandatory = $true, ValueFromPipeline = $true)]$PSSMSecret,
        [hashtable]$PSSMDatabase = $global:PSSMCurrentDatabase,
        [switch]$Force
    )
    Begin {}
    Process {
        if ($PSSMDatabase.containskey($PSSMSecret.SecretName) -and -not $Force) {
            throw "Secret with name $($PSSMSecret.SecretName) already exists in Database. Use another SecretName or parameter -Force to overwrite existing Secret"
        }
        $PSSMDatabase[$PSSMSecret.SecretName] = $PSSMSecret
    }
    End {}
}

Function Get-PSSMCredential {
    param(
        [Parameter (Mandatory = $true, ParameterSetName = 'PSSMSecret')]$PSSMSecret,
        [Parameter (Mandatory = $true, ParameterSetName = 'PSSMDB')][string]$SecretName,
        [Parameter (ParameterSetName = 'PSSMDB')][hashtable]$PSSMDatabase = $PSSMCurrentDatabase
    )
    if ($PsCmdlet.ParameterSetName -eq "PSSMDB") {
        if ($PSSMDatabase.containsKey($SecretName)) {
            $PSSMSecret = $PSSMDatabase[$SecretName]
        }
        Else {throw "Secret $SecretName Does not exist in Database $PSSMCurrentDatabasePath"}
    }
    $Base64Key = Get-CertDecryptedString -SourceString $PSSMSecret.EncryptedKey -CertThumbprint $PSSMSecret.CertThumbprint -UseMachineStorage:$PSSMSecret.UseMachineStorage
    $key = [convert]::FromBase64String($Base64Key)
    $SecurePassword = ConvertTo-SecureString -String $PSSMSecret.SecurePass -Key $key
    $Base64Key = $null
    $key = $null
    $cred = New-Object pscredential $PSSMSecret.UserName, $SecurePassword
    return $cred
}

Function Get-PSSMSecret {
    param(
        [string]$SecretName="*",
        [hashtable]$PSSMDatabase = $global:PSSMCurrentDatabase
    )
$KeyList = $PSSMDatabase.keys -like $SecretName
return $PSSMDatabase[$KeyList]
}