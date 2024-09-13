Function Invoke-SQLQuery {
    <#
    .SYNOPSIS
        Runs query against MSSQLServer database
    .PARAMETER text
        SQL command text.
    .PARAMETER base
        SQL Database Name
    .PARAMETER server
        SQL Server instance name
    .PARAMETER CommandType
        Optional. SQL Command type. Must be one of: 'StoredProcedure', 'TableDirect' or 'Text'. Default value is 'Text'.
    .PARAMETER CommandTimeout
        Optional. Timeout in seconds for sql query execution. Default value 30.
    .PARAMETER CommandTimeout
        Optional. Timeout in seconds for sql server connection.
    .PARAMETER params
        Optional. Hashtable with named attributes, wich will be sent to parameterised query.
    .PARAMETER ReturnDataset
        Optional switch parameter. If specified results will be returned in dataset. Otherwise Function returns array of rows.
    .OUTPUTS
        Query result. Output type depends on ReturnDataset parameter.
    #>
    [cmdletbinding()]
    Param(
        [parameter(Mandatory = $true)][String]$text,
        [parameter(Mandatory = $true)][String]$base,
        [parameter(Mandatory = $true)][String]$server,
        [parameter()][validateset('StoredProcedure', 'TableDirect', 'Text')][String]$CommandType = 'Text',
        [parameter(Mandatory = $true, ParameterSetName = "TokenAuth")][string]$AccessToken,
        [parameter(Mandatory = $true, ParameterSetName = "SQLAuth")][pscredential]$Credential,
        [parameter(Mandatory = $true, ParameterSetName = "WindowsAuth")][Switch]$WindowsAuth,
        [bool]$Encrypt = $true,
        [bool]$TrustServerCertificate = $False,
        [int]$CommandTimeout = 120,
        [int]$ConnTimeout = 15,
        [hashtable]$params = @{},
        [switch]$ReturnDataset
    )
    $ConnectionProperties = [ordered]@{
        'Server'                 = $server
        "Initial Catalog"        = $base
        "Connect Timeout"        = $ConnTimeout
        'Encrypt'                = $Encrypt
        'TrustServerCertificate' = $TrustServerCertificate
    }
    if ($WindowsAuth) {
        $ConnectionProperties["Integrated Security"] = "SSPI"
    }
    $ConnectionStringParts = @()
    foreach ($key in $ConnectionProperties.keys) {
        $ConnectionStringParts += "$key=$($ConnectionProperties[$key])"
    }
    $ConnectionString = $ConnectionStringParts -join ';'
    #"Data Source=$server;Initial Catalog=$base;Integrated Security=SSPI;Connect Timeout=$ConnTimeout"
    $Connection = new-Object Data.SqlClient.SqlConnection ($ConnectionString)
    if ($AccessToken) {
        $connection.AccessToken = $AccessToken
    }
    if($credential){
        $connection.Credential = [System.Data.SqlClient.SqlCredential]::new($Credential.UserName,$Credential.Password)
    }
    #"Server=tcp:ngl-center-dev-sqlmi.f21c46c32edf.database.windows.net,1433;Initial Catalog=glas_dev1;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30"
    $Command = new-Object Data.SqlClient.SqlCommand ($text, $Connection)
    Register-ObjectEvent -inputObject $Connection -eventName InfoMessage -Action { $event.SourceEventArgs.message  | Write-host -ForegroundColor DarkGreen } | Out-Null
    if ($params.count -gt 0) {
        foreach ($key  in $params.keys) {
            if ($null -ne $params[$key]) {
                $Command.Parameters.AddWithValue($key, $params[$key]) | Write-Debug
            }
            Else {
                $Command.Parameters.AddWithValue($key, [dbnull]::Value) | Write-Debug
            }
        }
    }
    $Command.CommandType = $commandtype
    $Command.CommandTimeout = $CommandTimeout
    $DataSet = new-Object Data.DataSet
    $DataAdapter = new-Object Data.SqlClient.SqlDataAdapter ($Command)
    $DataAdapter.Fill($DataSet) | Write-Debug
    if ($Connection.State -ne 'Closed') {
        $Connection.Close()
    }
    if ($ReturnDataset) { return $DataSet }
    Else { $dataset.tables | ForEach-Object { $_.rows } }
    trap {
        if ($Connection.State -ne 'Closed') {
            $Connection.Close()
        }
        Write-Error "Query to server $server failed :$_"
    }
} 

Function New-SQLUpsertQuery{
    [CmdletBinding()]
    param(
        [string]$TableName,
        [string[]]$UpsertFields,
        [string[]]$PKFields
    )
    $UpdateFields = $UpsertFields | Where-Object {$PKFields -notcontains $_}
    "SET NOCOUNT ON;
    MERGE INTO $TableName AS tgt
    USING
      (SELECT $(($PKFields | ForEach-Object {"@$_"}) -join ", ")) AS src ($(($PKFields | ForEach-Object {"[$_]"} ) -join ", "))
      ON $(($PKFields | ForEach-Object {"tgt.[$_] = src.[$_]"}) -join " and ")
    WHEN MATCHED THEN
        UPDATE
        SET $(($UpdateFields | ForEach-Object {"[$_] = @$_"}) -join ", ")
    WHEN NOT MATCHED THEN
        INSERT ($(($UpsertFields | ForEach-Object {"[$_]"}) -join ", ")) VALUES ($(($UpsertFields | ForEach-Object {"@$_"}) -join ", "));
    SET NOCOUNT OFF;"
}

Function Get-SQLTableColumns{
    param(
        [string[]]$Tablenames,
        [string]$SqlServer,
        [string]$Database
    )
    $params = @{}
    foreach ($Tablename in $Tablenames){
        $TablePath = @($Tablename -split "[\.](?![^[]*])")
        $cnt = $TablePath.count
        if ($cnt -gt 4) {Write-Error -Message "Wrong tablename syntax in: $tablename" -TargetObject $Tablename -ErrorAction Stop}
        [array]::Reverse($TablePath)
        $TableInfo = [pscustomobject][ordered]@{
            Server = $(if($cnt -gt 3){$TablePath[3].trim("[]")} else {$SqlServer})
            Database = $(if($cnt -gt 2){$TablePath[2].trim("[]")} else {$Database})
            Schema = $(if($cnt -gt 1){$TablePath[1].trim("[]")} else {"dbo"})
            Table = $TablePath[0].trim("[]")
        }
        $params["Table$($Tablenames.IndexOf($Tablename))"]="$($TableInfo.Database).$($TableInfo.Schema).$($TableInfo.Table)"
    }
    $Query = "SELECT c.TABLE_SCHEMA, c.TABLE_NAME, c.COLUMN_NAME, c.DATA_TYPE, tc.CONSTRAINT_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS c
    left join INFORMATION_SCHEMA.KEY_COLUMN_USAGE cu on c.TABLE_CATALOG = cu.TABLE_CATALOG
        and c.TABLE_SCHEMA = cu.TABLE_SCHEMA
        and c.TABLE_NAME = cu.TABLE_NAME
        and c.COLUMN_NAME = cu.COLUMN_NAME
    left join INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc on tc.CONSTRAINT_CATALOG = cu.CONSTRAINT_CATALOG
        and tc.CONSTRAINT_SCHEMA = cu.CONSTRAINT_SCHEMA
        and tc.CONSTRAINT_NAME = cu.CONSTRAINT_NAME
    WHERE concat(c.TABLE_CATALOG, '.', c.TABLE_SCHEMA,'.', c.TABLE_NAME) in
    ($(($params.keys | foreach-object {"@$_"}) -join " ,"))
    order by c.TABLE_SCHEMA, c.TABLE_NAME, c.ORDINAL_POSITION"
    $Dbf = Invoke-SQLQuery -server $SqlServer -base $Database -text $Query -params $params | Select-Object TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE, CONSTRAINT_TYPE | Group-Object TABLE_SCHEMA, TABLE_NAME
    $result = [ordered]@{}
    foreach ($table in $Dbf){
        $ResultKey = "$($table.group[0].TABLE_SCHEMA).$($table.group[0].TABLE_NAME)"
        $columns = [ordered]@{}
        foreach($column in $table.group){
            $columns[$column.COLUMN_NAME]=$column
        }
        $result[$ResultKey]=$columns
    }
    $result
}

Function New-SQLScriptOptions{
    param(
        [bool]$ExtendedProperties= $true,
        [bool]$DRIAll= $true,
        [bool]$Indexes= $true,
        [bool]$Triggers= $true,
        [bool]$ScriptBatchTerminator = $true,
        [bool]$IncludeDatabaseContext = $true,
        [bool]$IncludeHeaders = $false,
        [bool]$ToFileOnly = $true,
        [switch]$IncludeIfNotExists,
        [switch]$WithDependencies,
        [bool]$IncludeDatabaseRoleMemberships = $true,
        [bool]$Permissions = $true,
        [Text.Encoding]$Encoding = [text.encoding]::UTF8,
        [string]$Filename
    )
    $Options = [Microsoft.SqlServer.Management.SMO.ScriptingOptions]::New()
    foreach ($parameter in $MyInvocation.MyCommand.Parameters.keys){
        $Value = Get-Variable $parameter
        if ($PSBoundParameters.ContainsKey($parameter) -or ($null -ne $Value -and "" -ne $value))
            {
                $Options.$parameter = $Value.Value
            }
    }
        
    return $Options
}

Function Export-SQLDatabaseScripts{
    [CmdletBinding()]
    param(
        [parameter (Mandatory = $true)][string]$Server,
        [parameter (Mandatory = $true)][string]$Database,
        [parameter (Mandatory = $true)]$OutputFolderPath,
        [string[]]$StaticDataTableNames,
        [switch]$ScriptDrops,
        [bool]$AddNumericPrefix = $true,
        [int]$PrefixDigits=3
    )
    
    set-psdebug -strict
    $ErrorActionPreference = "stop" 
    
    $DefaultObjects = @(
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'public'}
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'db_owner'}
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'db_accessadmin'}
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'db_securityadmin'}
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'db_ddladmin'}
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'db_backupoperator'}
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'db_datareader'}
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'db_datawriter'}
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'db_denydatareader'}
        @{DatabaseObjectTypes = 'DatabaseRole'; Name = 'db_denydatawriter'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'DEFAULT'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/Notifications/EventNotification'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/Notifications/QueryNotification'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/BrokerConfigurationNotice/FailedRemoteServiceBinding'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/BrokerConfigurationNotice/FailedRoute'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/BrokerConfigurationNotice/MissingRemoteServiceBinding'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/BrokerConfigurationNotice/MissingRoute'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/DialogTimer'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/Error'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/ServiceDiagnostic/Description'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/ServiceDiagnostic/Query'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/ServiceDiagnostic/Status'}
        @{DatabaseObjectTypes = 'MessageType'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/ServiceEcho/Echo'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'dbo'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'guest'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'INFORMATION_SCHEMA'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'sys'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'db_owner'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'db_accessadmin'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'db_securityadmin'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'db_ddladmin'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'db_backupoperator'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'db_datareader'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'db_datawriter'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'db_denydatareader'}
        @{DatabaseObjectTypes = 'Schema'; Name = 'db_denydatawriter'}
        @{DatabaseObjectTypes = 'ServiceBroker'; Name = ''}
        @{DatabaseObjectTypes = 'ServiceContract'; Name = 'DEFAULT'}
        @{DatabaseObjectTypes = 'ServiceContract'; Name = 'http://schemas.microsoft.com/SQL/Notifications/PostEventNotification'}
        @{DatabaseObjectTypes = 'ServiceContract'; Name = 'http://schemas.microsoft.com/SQL/Notifications/PostQueryNotification'}
        @{DatabaseObjectTypes = 'ServiceContract'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/BrokerConfigurationNotice'}
        @{DatabaseObjectTypes = 'ServiceContract'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/ServiceDiagnostic'}
        @{DatabaseObjectTypes = 'ServiceContract'; Name = 'http://schemas.microsoft.com/SQL/ServiceBroker/ServiceEcho'}
        @{DatabaseObjectTypes = 'ServiceQueue'; Name = 'QueryNotificationErrorsQueue'}
        @{DatabaseObjectTypes = 'ServiceQueue'; Name = 'EventNotificationErrorsQueue'}
        @{DatabaseObjectTypes = 'ServiceQueue'; Name = 'ServiceBrokerQueue'}
        @{DatabaseObjectTypes = 'ServiceRoute'; Name = 'AutoCreatedLocal'}
        @{DatabaseObjectTypes = 'SqlAssembly'; Name = 'Microsoft.SqlServer.Types'}
        @{DatabaseObjectTypes = 'User'; Name = 'dbo'}
        @{DatabaseObjectTypes = 'User'; Name = 'guest'}
        @{DatabaseObjectTypes = 'User'; Name = 'INFORMATION_SCHEMA'}
        @{DatabaseObjectTypes = 'User'; Name = 'sys'}
    ) | ForEach-Object {[pscustomobject]$_}
    
    $SQLServer = [Microsoft.SqlServer.Management.Smo.Server]::new($Server)
    if ($null -eq $SQLServer.Version) {Throw "Can't find the instance $Server"}
    $db = $SQLServer.Databases[$Database] 
    if ($db.name -ne $Database){Throw "Can't find the database '$Database' in $Server"};
    if ($AddNumericPrefix){
        $prefixpattern = "0"*$PrefixDigits
        $counter = 0
        $prefix = "$($counter.tostring($prefixpattern))_"
        } else {$prefix = ""}
    $Filename = "$prefix$($Database)_Database.sql"
    $FilePath = Join-Path $OutputFolderPath $FileName;
    if (-not $(Test-path $OutputFolderPath)) {mkdir $OutputFolderPath}
    $Scripter = [Microsoft.SqlServer.Management.Smo.Scripter]::New($SQLServer)
    $ScriptOptions = New-SQLScriptOptions -Filename $FilePath
    $Scripter.Options = $ScriptOptions
    $Scripter.Script($SQLServer.databases[$Database])
    $all = [long][Microsoft.SqlServer.Management.Smo.DatabaseObjectTypes]::all `
        -bxor [Microsoft.SqlServer.Management.Smo.DatabaseObjectTypes]::ExtendedStoredProcedure
    $DBObjects=$SQLServer.databases[$Database].EnumObjects([long]0x1FFFFFFF -band $all) | Where-Object {('sys',"information_schema") -notcontains $_.Schema}
    $ToScript = Compare-Object $DBObjects $DefaultObjects -Property Name, DatabaseObjectTypes -PassThru | Where-Object {$_.SideIndicator -eq '<='}`
        | Select-Object *, @{n='objectId';e={$SQLServer.GetSmoObject($_.urn).id}} | Sort-Object -Property DatabaseObjectTypes, objectId
    foreach ($item in $ToScript){
        if ($AddNumericPrefix){
            $counter = $counter + 1
            $prefix = "$($counter.tostring($prefixpattern))_"
        } else {
            $prefix = ""
        }
        $ObjectType = $item.DatabaseObjectTypes
        $ObjectName = $item.Name -replace '[\\\/\:\.]','-'
        $Filename = "$prefix$($Database)_$($ObjectType)_$($ObjectName).sql"
        $FilePath = Join-Path $OutputFolderPath $FileName
        $scripter.Options.Filename = $FilePath
        $UrnCollection = [Microsoft.SqlServer.Management.Smo.urnCollection]::new()
        $URNCollection.add($item.urn)
        $scripter.script($URNCollection)
    }
    $UrnCollection = [Microsoft.SqlServer.Management.Smo.urnCollection]::new()
    if ($AddNumericPrefix){
        $prefix = "$("9"*$PrefixDigits)_"
    } else {
        $prefix = ""
    }
    $Filename = "$prefix$($Database)_StaticData.sql"
    $FilePath = Join-Path $OutputFolderPath $FileName
    $scripter.Options.Filename = $FilePath
    $scripter.Options.ScriptSchema = $False;
    $scripter.Options.ScriptData = $true;
    foreach ($item in $ToScript){
        if ($Item.DatabaseObjectTypes -eq 'Table'){
            foreach ($tn in $StaticDataTableNames){
                $TableName = $tn.trim() -split '.',0,'SimpleMatch'
                switch ($TableName.count)
                { 
                   1 { $obj = [pscustomobject]@{database=$database; Schema='dbo'; Table=$tablename[0]};  break}
                   2 { $obj = [pscustomobject]@{database=$database; Schema=$tablename[0]; Table=$tablename[1]};  break}
                   3 { $obj = [pscustomobject]@{database=$tablename[0]; Schema=$tablename[1]; Table=$tablename[2]};  break}
                   default {throw 'too many dots in the tablename'}
                }
                if ($Item.name -like $obj.table -and $Item.Schema -like $obj.Schema){
                    $UrnCollection.add($Item.urn)
                }
           }
        }
    }
    $Scripter.EnumScript($UrnCollection)
}

$Assembly = [System.Reflection.Assembly]::LoadWithPartialName( "Microsoft.SqlServer.SMO")
if ($Assembly.Evidence.version.major -gt 9) {
    $null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended")
}