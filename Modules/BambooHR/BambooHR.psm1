Function Invoke-BambooAPI {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true)][string]$ApiCall,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = 'Get',
        [object]$Body,
        [ValidateSet("XML","JSON")][string]$ExpectedDataFormat = "JSON",
        [ValidateSet("XML","JSON")][string]$RequestBodyFormat = "XML", #Default format for bamboo. Many methods support only XML Input
        [int]$MaxRetryCount = 5,
        [int]$RetryDelay = 100,
        [string]$ApiVer = 'v1',
        [switch]$ReturnRawData,
        [string]$Proxy
    )
    $dataformats = @{
        'XML' = "application/xml"
        'JSON' = "application/json"
    }
    $secpasswd = ConvertTo-SecureString "x" -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ([Net.NetworkCredential]::new("u",$ApiKey).password, $secpasswd)
    $uri = "https://api.bamboohr.com/api/gateway.php/${Subdomain}/${ApiVer}/${ApiCall}"
    Write-Verbose "Uri: $uri"
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $RetryCount = 0
    $doTry = $true
    while ($doTry) {
        try {
            $splat = @{Method = $Method; Uri = $uri; Credential = $Mycreds; Headers = @{Accept = $dataformats[$ExpectedDataFormat]}; DisableKeepAlive = $true; UseBasicParsing=$true}
            if ($PSBoundParameters.ContainsKey('Body')) {
                if ($Body -is [string]) {
                    $Body = [System.Text.Encoding]::UTF8.GetBytes($Body);
                }
                $splat['Body'] = $Body
                $splat.headers['Content-Type'] = $dataformats[$RequestBodyFormat]
            }
            if ($PSBoundParameters.ContainsKey('Proxy')) {
                if ($Proxy -ne ""){
                    $splat['Proxy'] = $Proxy
                }
            }
            $Responce = Invoke-WebRequest @Splat
            $Data = $Responce.content
            if ($ReturnRawData) {
                $Data
            }
            else {
                $ContentType = $Responce.Headers.'Content-Type' -split ';' | Where-Object {$_ -like "application/*"}
                switch ($ContentType){
                    'application/json' {
                        ConvertFrom-Json -InputObject $Data
                    }
                    'application/xml' {
                        [xml]$Data
                    }                    
                }
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
                Write-Error $_ -RecommendedAction Stop -TargetObject @{Method = $Method; Apicall = $ApiCall; Body = $Body}
            }
        }
    }
}

workflow Invoke-BambooAPIParallelCalls {
    param (
        [string[]]$ApiCallList,
        [securestring]$ApiKey,
        [string]$Subdomain,
        [string]$Proxy
    )
    foreach -parallel ($ApiCall in $ApiCallList) {
        Invoke-BambooAPI -ApiCall $ApiCall -Subdomain $Subdomain -ApiKey $ApiKey -Proxy $Proxy
    }
}

Function Get-BambooReport {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true, ParameterSetName = 'ID')][int]$ReportId,
        [parameter(ParameterSetName = 'ID')][switch]$FilterDuplicates,
        [parameter(Mandatory = $true, ParameterSetName = 'Custom')][string]$ReportRequest,
        [ValidateSet('CSV','PDF','XLS','XML','JSON')][string]$Format = 'JSON',
        [switch]$ReturnRawData,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
    )
    $splat = @{ApiKey = $ApiKey; Subdomain = $Subdomain; ReturnRawData = $true; Proxy = $proxy}
    if ($PSCmdlet.ParameterSetName -eq 'ID') {
        $fdm = @{$true = 'yes'; $false = 'no'}
        $fd = $fdm[$([bool]$FilterDuplicates)]
        $splat['ApiCall'] = "reports/${ReportId}/?format=$Format&fd=${fd}"
    }
    if ($PSCmdlet.ParameterSetName -eq 'Custom') {
        $splat['Method'] = 'POST'
        $splat['Body'] = $ReportRequest
        $splat['ApiCall'] = "reports/custom?format=$Format"
    }
    
    $responce = Invoke-BambooAPI @splat
    if (!$ReturnRawData){
        switch($format){
            'JSON' { return $(ConvertFrom-Json $responce) }
            'XML' {return $([xml]$responce)}
        }
    }
    return $responce
}

Function New-BambooReportRequest {
    [CmdletBinding()]param(
        [string[]]$Properties,
        [string]$Name = "CustomReport"
    )
    $fields = foreach ($Property in $Properties) {
        "<field id=`"$Property`" />"
    }
    "<report><title>$Name</title><fields>$($fields -join '')</fields></report>"
}

Function Get-BambooEmployee {
    [CmdletBinding()]param(
        [parameter(ParameterSetName = 'id',ValueFromPipeline = $true,ValueFromPipelineByPropertyName=$true)][Alias('employeeId')][int[]]$id,
        [string[]]$Properties,
        [switch]$IncludeNonameProperties,
        [parameter(ParameterSetName = 'id')][switch]$UseMultiRequest,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
    )
    Begin {
        $ApiCallList = New-Object System.Collections.ArrayList
        if ($Properties -contains '*') {
            $StandardFields = @("address1", "address2", "age", "bestEmail", "birthday", "city", "country", "dateOfBirth", "department", "division", "eeo", "employeeNumber", "employmentHistoryStatus", "ethnicity", "exempt", "firstName", "flsaCode", "fullName1", "fullName2", "fullName3", "fullName4", "fullName5", "displayName", "gender", "hireDate", "originalHireDate", "homeEmail", "homePhone", "id", "jobTitle", "lastChanged", "lastName", "location", "maritalStatus", "middleName", "mobilePhone", "payChangeReason", "payGroup", "payGroupId", "payRate", "payRateEffectiveDate", "payType", "payPer", "paidPer", "paySchedule", "payScheduleId", "payFrequency", "includeInPayroll", "preferredName", "ssn", "sin", "state", "stateCode", "status", "supervisor", "supervisorId", "supervisorEId", "terminationDate", "workEmail", "workPhone", "workPhonePlusExtension", "workPhoneExtension", "zipcode", "isPhotoUploaded", "standardHoursPerWeek", "bonusDate", "bonusAmount", "bonusReason", "bonusComment", "commissionDate", "commisionDate", "commissionAmount", "commissionComment")
            $FieldsMetadata = Invoke-BambooAPI -ApiCall "meta/fields/" -ApiKey $ApiKey -Subdomain $Subdomain -Proxy $Proxy
            $CustomFields = foreach($Metadata in $FieldsMetadata) {
                    if ([string]$($Metadata.alias) -ne '') {
                        if($UseMultiRequest){
                        $Metadata.alias
                        }else{
                            $Metadata.id
                        }
                    }
                    else {
                        if ($IncludeNonameProperties) {
                            $Metadata.id
                        }
                    }
                }
            $Fields = $StandardFields + $CustomFields | Select-Object -Unique | Sort-Object
        }
        else {
            $DefaultFields = ("employeeNumber", "firstName", "lastName", "workEmail", "jobTitle", "department", "Status")
            $Fields = $DefaultFields + $Properties | Select-Object -Unique | Sort-Object
        }
        $Fieldlist = $Fields -join ","
        [collections.arraylist]$ids = $id
    }
    process {
        if ($PSBoundParameters.ContainsKey('id')) {
            $ids += $id
        }
    }
    End {
        if ($UseMultiRequest){
            if (-not ($PSBoundParameters.ContainsKey('id'))) {
                $ChangeList = Invoke-BambooAPI -ApiCall "employees/changed/?since=2000-01-01T00:00:00Z" -Subdomain $Subdomain -ApiKey $ApiKey -Proxy $Proxy
                $employeeids = ($ChangeList.employees | Get-Member -MemberType NoteProperty).name | Where-Object {$ChangeList.employees.$_.action -ne 'deleted'}
                foreach ($id in $employeeids) {
                    $null = $ApiCallList.Add("employees/${id}?fields=${Fieldlist}")
                }
            } else {
                foreach ($id in $ids){
                    $null = $ApiCallList.Add("employees/${id}?fields=${Fieldlist}")
                }
             }
            Invoke-BambooAPIParallelCalls -ApiCallList $ApiCallList -ApiKey $ApiKey -Subdomain $Subdomain -Proxy $Proxy
        }
        else{
            $ReportRequest = New-BambooReportRequest -Properties $Fields
            $Report = Get-BambooReport -ReportRequest $ReportRequest -Format JSON -Subdomain $Subdomain -ApiKey $ApiKey
            $Fields = @('id')+$Report.fields.id
            foreach ($item in $Report.employees){
                $Employee = [ordered]@{}
                foreach ($Field in $Fields){
                    $Employee[$Field]=$item.$Field
                }
                if ((-not ($PSBoundParameters.ContainsKey('id')) -or ($ids -contains $Employee.id))){
                    [pscustomobject]$Employee
                }
            }
        }
    }
}

Function Get-BambooEmployeeTable {
    [CmdletBinding()]param(
        [parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName=$true)][Alias('employeeId')][int]$id,
        [parameter(Mandatory = $true)][ValidatePattern("^[a-zA-Z\d]+$")][string]$TableName,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
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
            $apiCall = "employees/all/tables/$($TableName)"
            Invoke-BambooAPI -ApiCall $ApiCall -Subdomain $Subdomain -ApiKey $ApiKey -Proxy $Proxy
        } else {
            Invoke-BambooAPIParallelCalls -ApiCallList $ApiCallList -ApiKey $ApiKey -Subdomain $Subdomain -Proxy $Proxy
        }
    }
}

Function Get-BambooDirectory {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [switch]$ReturnFieldlist,
        [string]$Proxy
    )
    $ApiCall = "employees/directory"
    $result = Invoke-BambooAPI -ApiCall $ApiCall -ApiKey $ApiKey -Subdomain $Subdomain -Proxy $Proxy
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
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
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
    Invoke-BambooAPI -ApiCall $ApiCall -ApiKey $ApiKey -Subdomain $Subdomain -Proxy $Proxy
}

Function Get-BambooJobInfoOnDate {
    [CmdletBinding()]param(
        [parameter(Mandatory = $true, ParameterSetName = 'Online')][int]$EmployeeId,
        [parameter(Mandatory = $true, ParameterSetName = 'Cached')][array]$Jobinfo,
        [parameter(Mandatory = $true)][datetime]$date,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
    )
    if ($PSCmdlet.ParameterSetName -eq 'Online') {
        $Jobinfo = Get-BambooEmployeeTable -id $EmployeeId -TableName 'jobInfo' -Subdomain $Subdomain -ApiKey $ApiKey -Proxy $proxy
    }
    $JobInfo = $Jobinfo | Sort-Object -Property date -Descending
    foreach ($item in $Jobinfo) {
        if ($date -ge $([datetime]$item.date)) {
            return $item
            break
        }
    }
}

Function Get-BambooMetadata{
    [CmdletBinding()]param(
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
    )
    $Fields = Invoke-BambooAPI 'meta/fields' -ApiKey $ApiKey -Subdomain $Subdomain -Proxy $Proxy
    $Lists = Invoke-BambooAPI 'meta/lists' -ApiKey $ApiKey -Subdomain $Subdomain -Proxy $Proxy
    $Tables = Invoke-BambooAPI 'meta/tables' -ApiKey $ApiKey -Subdomain $Subdomain -ReturnRawData -Proxy $Proxy
    $metadata = @{}
    foreach ($Field in $Fields){
        $metadata[$field.id.tostring()]=[pscustomobject]@{
            id=$field.id.tostring()
            Name = $Field.name
            datatype = $Field.type
            alias = $Field.alias
            FieldType = 'Field'
            ParentObject = 'Employee'
            
        }
    }

    foreach ($List in $lists){
        if(!$metadata.ContainsKey($list.fieldId.tostring())){
            $metadata[$field.id.tostring()]=[pscustomobject]@{
                id=$list.fieldId.tostring()
                Name = $list.Name
                datatype = 'list'
                alias = $list.alias
                FieldType = 'List'
                ParentObject = 'Employee'
                
            }
        } else{
            $metadata[$list.fieldId.tostring()].alias = $list.alias
            $metadata[$list.fieldId.tostring()].Name = $list.Name
            $metadata[$list.fieldId.tostring()].FieldType = 'List'
        }
    }

    foreach ($table in $tables){
        foreach ($field in $table.field){
            if(!$metadata.ContainsKey($field.id.tostring())){
                $metadata[$field.id.tostring()]=[pscustomobject]@{
                    id=$field.id.tostring()
                    Name = $Field.'#text'
                    datatype = $Field.type
                    alias = $Field.alias
                    FieldType = 'TableColumn'
                    ParentObject = $table.Alias
                }
            } else{
                $metadata[$field.id.tostring()].alias = $field.alias
                $metadata[$field.id.tostring()].Name = $Field.'#text'
                $metadata[$field.id.tostring()].datatype = $Field.type
                $metadata[$field.id.tostring()].FieldType = 'TableColumn'
                $metadata[$field.id.tostring()].ParentObject = $table.Alias
            }
        }
    }
return $metadata
}

Function Get-BambooListItems{
    [CmdletBinding()]param(
        [parameter(Mandatory = $true, ParameterSetName = 'Name')][string]$Name,
        [parameter(Mandatory = $true, ParameterSetName = 'Alias')][string]$Alias,
        [parameter(Mandatory = $true, ParameterSetName = 'FieldID')][int]$FieldID,
        [switch]$IncludeArchived,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
    )

    if ($PSCmdlet.ParameterSetName -eq 'FieldID'){
        $ApiCall = "meta/lists/$FieldID"
    } else {
        $ApiCall = "meta/lists"
    }
    $res = Invoke-BambooAPI -ApiCall $ApiCall -ApiKey $ApiKey -Subdomain $Subdomain -Proxy $Proxy
    if ($PSCmdlet.ParameterSetName -eq 'Name'){$res = $res | Where-Object {$_.name -eq $Name}}
    if ($PSCmdlet.ParameterSetName -eq 'Alias'){$res = $res | Where-Object {$_.name -eq $Alias}}
    if ($IncludeArchived){
        $res.options
    } else {
        $res.options | Where-Object {$_.archived -eq 'no'}
    }
}

Function Set-BambooEmployee {
    [CmdletBinding()]param(
        [parameter(ValueFromPipelineByPropertyName)][Alias('employeeId')][int]$id,
        [hashtable]$Replace,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
    )
    Begin {
        $Fields = foreach ($key in $Replace.keys) {
            "<field id=`"$key`">$([System.Security.SecurityElement]::Escape($Replace[$key]))</field>"
        }
        $Body = "<employee>$($Fields -join '')</employee>"
    }
    Process {
        Invoke-BambooAPI -Subdomain $Subdomain -ApiKey $ApiKey -Method Post -ApiCall "employees/$id" -Body $Body -Proxy $Proxy
    }
    
}

Function Set-BambooListItem{
    [CmdletBinding()]param(
        [parameter(Mandatory=$true)][int]$ListId,
        [parameter(ValueFromPipelineByPropertyName)][int]$ItemId,
        [parameter(ValueFromPipelineByPropertyName)][String]$ItemValue,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
    )
    Begin{
        [collections.ArrayList]$Options = @()
    }
    Process{
        $ItemValueEnc = [System.Security.SecurityElement]::Escape($ItemValue)
        $null = $Options.add("<option id=`"$ItemId`">$ItemValueEnc</option>")
    }
    End{
        $ApiCall = "meta/lists/$ListId"
        $Body = "<options>$($Options -join '')</options>"
        Invoke-BambooAPI -Subdomain $Subdomain -ApiKey $ApiKey -ApiCall $ApiCall -Method Put -Body $Body -ReturnRawData -Proxy $Proxy
    }
}

Function Add-BambooListItem{
    [CmdletBinding()]param(
        [parameter(Mandatory=$true)][int]$ListId,
        [parameter(ValueFromPipeline=$true)][String]$ItemValue,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
    )
    Begin{
        [collections.ArrayList]$Options = @()
    }
    Process{
        $ItemValueEnc = [System.Security.SecurityElement]::Escape($ItemValue)
        $null = $Options.add("<option>$ItemValueEnc</option>")
    }
    End{
        $ApiCall = "meta/lists/$ListId"
        $Body = "<options>$($Options -join '')</options>"
        Invoke-BambooAPI -Subdomain $Subdomain -ApiKey $ApiKey -ApiCall $ApiCall -Method Put -Body $Body -ReturnRawData -Proxy $Proxy
    }
}

Function Set-BambooEmployeeTableRow{
    [CmdletBinding()]param(
        [parameter(ValueFromPipelineByPropertyName)][Alias('employeeId')][int]$id,
        [parameter(Mandatory = $true)][string]$TableName,
        [parameter(Mandatory = $true)][int]$RowId,
        [hashtable]$Replace,
        [parameter(Mandatory = $true)][string]$Subdomain,
        [parameter(Mandatory = $true)][securestring]$ApiKey,
        [string]$Proxy
    )
    Begin {
        $Fields = foreach ($key in $Replace.keys) {
            $Value = $Replace[$key]
            if ($Value -is [datetime]){
                $value = $Value.ToString('yyyy-MM-dd')
            }
            "<field id=`"$key`">$Value</field>"
        }
        $Body = "<row>$($Fields -join '')</row>"
    }
    Process {
        $ApiCall = "employees/$id/tables/$TableName/$RowId"
        Invoke-BambooAPI -Subdomain $Subdomain -ApiKey $ApiKey -Method Post -ApiCall $ApiCall -Body $Body -Proxy $Proxy
    }
}