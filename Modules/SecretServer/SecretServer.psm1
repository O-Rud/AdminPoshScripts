Function Get-SecretServerCredentials {
     <#
    .SYNOPSIS
        Requests credentials from Secret Server
    .DESCRIPTION
        Get-SecretServerCredentials uses REST API to query Secret Server and get a specific secret. Returnes secret wrapped in PSCredential object.
    .PARAMETER SecretId
        Numeric ID of secret in secret server
	.PARAMETER SecretServerURL
        URL of Secret Server
    .PARAMETER GetExtendedInfo
        If Function called with this parameter, additional info will be returned. Otherwise only PSCredential object is returned
	.OUTPUTS
        If called with -GetExtendedInfo PSCustomObject with all secret fields is returned. Credential stored in Credential Field. Otherwise PSCredential object is returned
    #>
    param(
        [int]$SecretId,
        [string]$SecretServerURL = "https://secretserver.home24.lan:44300",
        [switch]$GetExtendedInfo
    )
    $api = "$SecretServerURL/winauthwebservices/api/v1"
    $endpoint = "$api/secrets/$secretId"
    $SHT = @{}
    $secret = Invoke-RestMethod $endpoint -UseDefaultCredentials
    $secret.items | ForEach-Object {$SHT[$_.fieldname] = $_.itemvalue}
    $secpasswd = ConvertTo-SecureString $SHT.Password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ($SHT.Username, $secpasswd)
    if ($GetExtendedInfo) {
        $SHT.Remove('Username')
        $SHT.Remove('Password')
        $SHT['Credential'] = $cred
        [pscustomobject]$sht
    }
    else {
        $cred
    }
}
