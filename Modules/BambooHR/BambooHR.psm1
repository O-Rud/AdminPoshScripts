Function Invoke-BambooAPI {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true)][string]$ApiCall,
        [parameter(Mandatory = $true)][string]$ApiKey,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = 'Get',
        [object]$Body,
        [int]$MaxRetryCount = 5,
        [int]$RetryDelay = 100,
        [string]$ApiVer = 'v1',
        [switch]$ReturnRawData
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
            $splat = @{Method = $Method; Uri = $uri; Credential = $Mycreds; Headers = @{Accept = "application/json"}; DisableKeepAlive = $true}
            if ($PSBoundParameters.ContainsKey('Body')) {
                $splat['Body'] = $Body
            }
            $Responce = Invoke-WebRequest @Splat
            $Data = $Responce.content
            if ($ReturnRawData) {
                $Data
            }
            else {
                ConvertFrom-Json -InputObject $Data
            }
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

workflow Invoke-BambooAPIParallelCalls {
    param (
        [string[]]$ApiCallList,
        [string]$ApiKey,
        [string]$Subdomain
    )
    foreach -parallel ($ApiCall in $ApiCallList) {
        Invoke-BambooAPI -ApiCall $ApiCall -Subdomain $Subdomain -ApiKey $ApiKey
    }
}

Function Get-BambooReport {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true, ParameterSetName = 'ID')][int]$ReportId,
        [parameter(ParameterSetName = 'ID')][switch]$FilterDuplicates,
        [parameter(ParameterSetName = 'Custom')][switch]$CustomReport,
        [parameter(Mandatory = $true, ParameterSetName = 'Custom')][string]$ReportRequest,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    $splat = @{ApiKey = $ApiKey; Subdomain = $Subdomain}
    if ($PSCmdlet.ParameterSetName -eq 'ID') {
        $fdm = @{$true = 'yes'; $false = 'no'}
        $fd = $fdm[$([bool]$FilterDuplicates)]
        $splat['ApiCall'] = "reports/${ReportId}/?format=json&fd=${fd}"
    }
    if ($PSCmdlet.ParameterSetName -eq 'Custom') {
        $splat['Method'] = 'POST'
        $splat['Body'] = $ReportRequest
        $splat['ApiCall'] = 'reports/custom?format=json'
    }
    
    Invoke-BambooAPI @splat
}

Function New-BambooReportRequest {
    [CmdletBinding()]param(
        [string[]]$Properties,
        [string]$Name = "CustomReport",
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    $fields = foreach ($Property in $Properties) {
        "<field id=`"$Property`" />"
    }
    "<report><title>$Name</title><fields>$($fields -join '')</fields></report>"
}

Function Get-BambooEmployee {
    [CmdletBinding()]param(
        [parameter(ValueFromPipelineByPropertyName)][Alias('employeeId')][int]$id,
        [string[]]$Properties,
        [switch]$IncludeNonameProperties,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    Begin {
        $ApiCallList = New-Object System.Collections.ArrayList
        if ($Properties -contains '*') {
            $StandardFields = @("address1", "address2", "age", "bestEmail", "birthday", "city", "country", "dateOfBirth", "department", "division", "eeo", "employeeNumber", "employmentHistoryStatus", "ethnicity", "exempt", "firstName", "flsaCode", "fullName1", "fullName2", "fullName3", "fullName4", "fullName5", "displayName", "gender", "hireDate", "originalHireDate", "homeEmail", "homePhone", "id", "jobTitle", "lastChanged", "lastName", "location", "maritalStatus", "middleName", "mobilePhone", "payChangeReason", "payGroup", "payGroupId", "payRate", "payRateEffectiveDate", "payType", "payPer", "paidPer", "paySchedule", "payScheduleId", "payFrequency", "includeInPayroll", "preferredName", "ssn", "sin", "state", "stateCode", "status", "supervisor", "supervisorId", "supervisorEId", "terminationDate", "workEmail", "workPhone", "workPhonePlusExtension", "workPhoneExtension", "zipcode", "isPhotoUploaded", "standardHoursPerWeek", "bonusDate", "bonusAmount", "bonusReason", "bonusComment", "commissionDate", "commisionDate", "commissionAmount", "commissionComment")
            $FieldsMetadata = Invoke-BambooAPI -ApiCall "meta/fields/" -ApiKey $ApiKey -Subdomain $Subdomain
            $CustomFields = $FieldsMetadata.foreach( {
                    if ([string]$($_.alias) -ne '') {
                        $_.alias
                    }
                    else {
                        if ($IncludeNonameProperties) {
                            $_.id
                        }
                    }
                })
            $Fields = $StandardFields + $CustomFields | Select-Object -Unique | Sort-Object
        }
        else {
            $DefaultFields = ("employeeNumber", "firstName", "lastName", "workEmail", "jobTitle", "department", "Status")
            $Fields = $DefaultFields + $Properties | Select-Object -Unique
        }
        $Fieldlist = $Fields -join ","
    }
    process {
        if ($PSBoundParameters.ContainsKey('id')) {
            $null = $ApiCallList.Add("employees/${id}?fields=${Fieldlist}")
        }
    }
    End {
        if (-not ($PSBoundParameters.ContainsKey('id'))) {
            $ChangeList = Invoke-BambooAPI -ApiCall "employees/changed/?since=2000-01-01T00:00:00Z" -Subdomain $Subdomain -ApiKey $ApiKey
            $employeeids = ($ChangeList.employees | Get-Member -MemberType NoteProperty).name | Where-Object {$ChangeList.employees.$_.action -ne 'deleted'}
            foreach ($id in $employeeids) {
                $null = $ApiCallList.Add("employees/${id}?fields=${Fieldlist}")
            }
        }
        Invoke-BambooAPIParallelCalls -ApiCallList $ApiCallList -ApiKey $ApiKey -Subdomain $Subdomain
    }
}

Function Get-BambooEmployeeTable {
    [CmdletBinding()]param(
        [parameter(ValueFromPipelineByPropertyName)][Alias('employeeId')][int]$id,
        [parameter(Mandatory = $true)][ValidatePattern("^[a-zA-Z\d]+$")][string]$TableName,
        [switch]$RequireRowIds,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    Begin {
        $ApiCallList = New-Object System.Collections.ArrayList
    }
    process {
        if ($PSBoundParameters.ContainsKey('id')) {
            $null = $ApiCallList.Add("employees/${id}/tables/$TableName")
        }
    }
    End {
        if (-not ($PSBoundParameters.ContainsKey('id'))) {
            if ($RequireRowIds){
                $ChangeList = Invoke-BambooAPI -ApiCall "employees/changed/?since=2000-01-01T00:00:00Z" -Subdomain $Subdomain -ApiKey $ApiKey
                $employeeids = ($ChangeList.employees | Get-Member -MemberType NoteProperty).name | Where-Object {$ChangeList.employees.$_.action -ne 'deleted'}
                foreach ($id in $employeeids) {
                    $null = $ApiCallList.Add("employees/${id}/tables/$Tablename")
                }
                Invoke-BambooAPIParallelCalls -ApiCallList $ApiCallList -ApiKey $ApiKey -Subdomain $Subdomain
            }
            $apiCall = "employees/changed/tables/$($TableName)?since=2000-01-01T00:00:00Z"
            $res = Invoke-BambooAPI -ApiCall $ApiCall -Subdomain $Subdomain -ApiKey $ApiKey
            $Ids = $res.employees | Get-Member -MemberType noteproperty | ForEach-Object {[int]$($_.name)} | Sort-Object
            foreach ($id in $Ids){
                foreach ($row in $($res.employees.$id).rows){
                    $row | Select-Object @{n='employeeid';e={$id}},*
                }
            }

        } else {
            Invoke-BambooAPIParallelCalls -ApiCallList $ApiCallList -ApiKey $ApiKey -Subdomain $Subdomain

        }
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

Function Get-BambooTimeOffRequests {
    [CmdletBinding()]param(
        [int]$RequestId,
        [int]$EmployeeId,
        [datetime]$Start,
        [datetime]$End,
        [int]$TypeId,
        [ValidateSet('approved', 'denied', 'superceded', 'requested', 'canceled')][string]$Status,
        [ValidateSet("view", "approve")][string]$Action,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    $Filter = @{}
    if ($PSBoundParameters.ContainsKey('RequestId')) {
        $Filter['id'] = $RequestId
    }
    if ($PSBoundParameters.ContainsKey('EmployeeId')) {
        $Filter['employeeId'] = $EmployeeId
    }
    if ($PSBoundParameters.ContainsKey('TypeId')) {
        $Filter['type'] = $TypeId
    }
    if ($PSBoundParameters.ContainsKey('Start')) {
        $Filter['start'] = $Start.ToString('yyyy-MM-dd')
    }
    if ($PSBoundParameters.ContainsKey('End')) {
        $Filter['end'] = $End.ToString('yyyy-MM-dd')
    }
    if ($PSBoundParameters.ContainsKey('Action')) {
        $Filter['action'] = $Action
    }
    if ($PSBoundParameters.ContainsKey('Status')) {
        $Filter['status'] = $Status
    }
    if ($Filter.Keys.Count -gt 0) {
        $FilterList = foreach ($key in $Filter.keys) {"$key=$($Filter[$key])"}
        $FilterString = "?$($Filterlist -join '&')"
    }
    $ApiCall = "time_off/requests/$FilterString"
    Invoke-BambooAPI -ApiCall $ApiCall -ApiKey $ApiKey -Subdomain $Subdomain
}

Function Get-BambooJobInfoOnDate {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true, ParameterSetName = 'Online')][int]$EmployeeId,
        [parameter(Mandatory = $true, ParameterSetName = 'Cached')][array]$Jobinfo,
        [parameter(Mandatory = $true)][datetime]$date,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    if ($PSCmdlet.ParameterSetName -eq 'Online') {
        $Jobinfo = Get-BambooEmployeeTable -id $EmployeeId -TableName 'jobInfo' -Subdomain $Subdomain -ApiKey $ApiKey
    }
    $JobInfo = $Jobinfo | Sort-Object -Property date -Descending
    foreach ($item in $Jobinfo) {
        if ($date -ge $([datetime]$item.date)) {
            return $item
            break
        }
    }
}

Function Set-BambooEmployee {
    [CmdletBinding()]param(
        [parameter(ValueFromPipelineByPropertyName)][Alias('employeeId')][int]$id,
        [hashtable]$Replace,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    Begin {
        $Fields = foreach ($key in $Replace.keys) {
            "<field id=`"$key`">$($Replace[$key])</field>"
        }
        $Body = "<employee>$($Fields -join '')</employee>"
    }
    Process {
        Invoke-BambooAPI -Subdomain $Subdomain -ApiKey $ApiKey -Method Post -ApiCall "employees/$id" -Body $Body
    }
    
}

Function Set-BambooListItem{
    [CmdletBinding()]param(
        [parameter(Mandatory=$true)][int]$ListId,
        [parameter(ValueFromPipelineByPropertyName)][int]$ItemId,
        [parameter(ValueFromPipelineByPropertyName)][String]$ItemValue,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    Begin{
        [collections.ArrayList]$Options = @()
    }
    Process{
        $null = $Options.add("<option id=`"$ItemId`">$ItemValue</option>")
    }
    End{
        $ApiCall = "meta/lists/$ListId"
        $Body = "<options>$($Options -join '')</options>"
        Invoke-BambooAPI -Subdomain $Subdomain -ApiKey $ApiKey -ApiCall $ApiCall -Method Put -Body $Body -ReturnRawData
    }
}

Function Set-BambooEmployeeTableRow{
    [CmdletBinding()]param(
        [parameter(ValueFromPipelineByPropertyName)][Alias('employeeId')][int]$id,
        [parameter(Mandatory = $true)][string]$TableName,
        [parameter(Mandatory = $true)][int]$RowId,
        [hashtable]$Replace,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][string]$ApiKey
    )
    Begin {
        $Fields = foreach ($key in $Replace.keys) {
            "<field id=`"$key`">$($Replace[$key])</field>"
        }
        $Body = "<row>$($Fields -join '')</row>"
    }
    Process {
        $ApiCall = "employees/$id/tables/$TableName/$RowId"
        Invoke-BambooAPI -Subdomain $Subdomain -ApiKey $ApiKey -Method Post -ApiCall $ApiCall -Body $Body
    }
    
}