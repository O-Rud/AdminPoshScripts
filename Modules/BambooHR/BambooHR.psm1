Function Invoke-BambooAPI {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true)][string]$ApiCall,
        [parameter(Mandatory = $true)][string]$ApiKey,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [int]$MaxRetryCount = 5,
        [int]$RetryDelay = 100,
        [string]$ApiVer = 'v1'
    )
    $secpasswd = ConvertTo-SecureString "x" -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($ApiKey, $secpasswd)
    $uri = "https://api.bamboohr.com/api/gateway.php/${Subdomain}/${ApiVer}/${ApiCall}"
    Write-Verbose "Uri: $uri"
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $RetryCount = 0
    $doTry = $true
    while ($doTry) {
        try {
            Invoke-RestMethod -Method Get -Uri $uri -Credential $mycreds -Headers @{Accept = "application/json"} -DisableKeepAlive
            $doTry = $false
        }
        catch {
            $statuscode = $_.InnerException.Response.StatusCode.value__
            if ((500..599) -contains $statuscode -and $RetryCount -lt $MaxRetryCount) {
                Write-Debug $_
                ++$RetryCount
            }
            else {
                $doTry = $false
                Write-Error $_ -RecommendedAction Stop
            }
        }
    }

}

Function Get-BambooEmployee {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName)][int]$id,
        [string[]]$Properties,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    Begin {
        if ($Properties -contains '*') {
            $FieldsMetadata = Invoke-BambooAPI -ApiCall "meta/fields/" -ApiKey $ApiKey -Subdomain $Subdomain
            $Fields = $FieldsMetadata.foreach( {if ([string]$($_.alias) -ne '') {$_.alias} else {$_.id}})
        }
        else {
            $DefaultFields = ("employeeNumber", "firstName", "lastName", "workEmail", "jobTitle", "department", "Status")
            $Fields = $DefaultFields + $Properties | Select-Object -Unique
        }
        $Fieldlist = $Fields -join ","
    }
    process {
        $ApiCall = "employees/${id}?fields=${Fieldlist}"
        Invoke-BambooAPI -ApiCall $ApiCall -ApiKey $ApiKey -Subdomain $Subdomain
    }
}

Function Get-BambooDirectory {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey,
        [switch]$ReturnFieldlist
    )
    $ApiCall = "employees/directory"
    $result = Invoke-BambooAPI -ApiCall $ApiCall -ApiKey $ApiKey -Subdomain $Subdomain
    if ($ReturnFieldlist) { $result} else {
        $result.employees
    }
    


}