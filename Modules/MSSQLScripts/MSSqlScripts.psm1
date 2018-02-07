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
		Optional parameter. SQL Command type. Must be one of: 'StoredProcedure', 'TableDirect' or 'Text'. Default value is 'Text'.
	.PARAMETER CommandTimeout
		Optional parameter. Timeout in seconds for sql query execution. Default value 30.
	.PARAMETER CommandTimeout
		Optional parameter. Timeout in seconds for sql server connection.
	.PARAMETER params
		Optional paremeter. Hashtable with named attributes, wich will be sent to parameterised query.
	.PARAMETER ReturnDataset
		Optional switch parameter. If specified results will be returned in dataset. Otherwise Function returns array of rows.
    .OUTPUTS
        Query result. Output type depends on ReturnDataset parameter.
    #>
    Param(
        [parameter(Mandatory = $true)][String]$text,
        [parameter(Mandatory = $true)][String]$base,
        [parameter(Mandatory = $true)][String]$server,
        [parameter()][validateset('StoredProcedure', 'TableDirect', 'Text')][String]$CommandType = 'Text',
        [String]$CommandTimeout = 30,
        [String]$ConnTimeout = 15,
        [hashtable]$params = @{},
        [switch]$ReturnDataset
    )
    $ConnectionString = "Data Source=$server;Initial Catalog=$base;Integrated Security=SSPI;Connect Timeout=$ConnTimeout"
    $Connection = new-Object Data.SqlClient.SqlConnection ($ConnectionString)
    $Command = new-Object Data.SqlClient.SqlCommand ($text, $Connection)
    Register-ObjectEvent -inputObject $Connection -eventName InfoMessage -Action {$event.SourceEventArgs.message  | Write-host -ForegroundColor DarkGreen} | Out-Null
    if ($params.count -gt 0) {
        foreach ($key  in $params.keys) {
            if ($params[$key] -ne $null) {
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
    if ($ReturnDataset) {return $DataSet}
    Else {$dataset.tables | % {$_.rows}}
    trap {
        if ($Connection.State -ne 'Closed') {
            $Connection.Close()
        }
        Write-Error "Query to server $server failed :$_"
    }
} #End Function Invoke-SQLQuery

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
      (SELECT $(($PKFields | ForEach-Object {"@$_"}) -join ", ")) AS src ($($PKFields -join ", "))
      ON $(($PKFields | ForEach-Object {"tgt.$_ = src.$_"}) -join " and ")
    WHEN MATCHED THEN
        UPDATE
        SET $(($UpdateFields | ForEach-Object {"$_ = @$_"}) -join ", ")
    WHEN NOT MATCHED THEN
        INSERT ($($UpsertFields -join ", ")) VALUES ($(($UpsertFields | ForEach-Object {"@$_"}) -join ", "));
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
        $params["Table$($Tablenames.IndexOf($Tablename))"]=$Tablename
    }
    $Query = "SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME in ($(($params.keys | foreach-object {"@$_"}) -join " ,"))"
    $Dbf = Invoke-SQLQuery -server $SqlServer -base $Database -text $Query -params $params | Select-Object TABLE_NAME, COLUMN_NAME, DATA_TYPE | Group-Object TABLE_NAME
    $result = @{}
    foreach ($table in $Dbf){
        $columns = @{}
        foreach($column in $table.group){
            $columns[$column.COLUMN_NAME]=$column.DATA_TYPE
        }
        $result[$table.name]=$columns
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
        [bool]$IncludeHeaders = $true,
        [bool]$ToFileOnly = $true,
        [switch]$IncludeIfNotExists,
        [switch]$WithDependencies,
        [bool]$IncludeDatabaseRoleMemberships = $true,
        [bool]$Permissions = $true,
        [string]$Filename
    )
    $Options = [Microsoft.SqlServer.Management.SMO.ScriptingOptions]::New()
    foreach ($parameter in $MyInvocation.MyCommand.Parameters.keys){
        $Value = Get-Variable $parameter
        if ($PSBoundParameters.ContainsKey($parameter) -or ($Value -ne $null -and $value -ne ""))
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
        [switch]$ScriptDrops
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
    if ($SQLServer.Version -eq  $null ){Throw "Can't find the instance $Server"}
    $db = $SQLServer.Databases[$Database] 
    if ($db.name -ne $Database){Throw "Can't find the database '$Database' in $Server"};
    $Filename = "$($Database)_Database.sql"
    $FilePath = Join-Path $OutputFolderPath $FileName;
    if (-not $(Test-path $OutputFolderPath)) {mkdir $OutputFolderPath}
    $Scripter = [Microsoft.SqlServer.Management.Smo.Scripter]::New($SQLServer)
    $ScriptOptions = New-SQLScriptOptions -Filename $FilePath
    $Scripter.Options = $ScriptOptions
    $Scripter.Script($SQLServer.databases[$Database])
    $all = [long][Microsoft.SqlServer.Management.Smo.DatabaseObjectTypes]::all `
        -bxor [Microsoft.SqlServer.Management.Smo.DatabaseObjectTypes]::ExtendedStoredProcedure
    $DBObjects=$SQLServer.databases[$Database].EnumObjects([long]0x1FFFFFFF -band $all) | Where-Object {('sys',"information_schema") -notcontains $_.Schema}
    $ToScript = Compare-Object $DBObjects $DefaultObjects -Property Name, DatabaseObjectTypes -PassThru | Where-Object {$_.SideIndicator -eq '<='}
    [collections.arraylist]$TablesToExport = @()
    # foreach ($item in $ToScript){
    #     if ($Item.DatabaseObjectTypes -eq 'Table'){
    #         foreach ($tn in $StaticDataTableNames){
    #             $TableName = $tn.trim() -split '.',0,'SimpleMatch'
    #             switch ($TableName.count)
    #             { 
    #               1 { $obj = [pscustomobject]@{database=$database; Schema='dbo'; Table=$tablename[0]};  break}
    #               2 { $obj = [pscustomobject]@{database=$database; Schema=$tablename[0]; Table=$tablename[1]};  break}
    #               3 { $obj = [pscustomobject]@{database=$tablename[0]; Schema=$tablename[1]; Table=$tablename[2]};  break}
    #               default {throw 'too many dots in the tablename'}
    #             }
    #         }
    #     }
    # }
    foreach ($item in $ToScript){
        $ObjectType = $item.DatabaseObjectTypes
        $ObjectName = $item.Name -replace '[\\\/\:\.]','-'
        $Filename = "$($Database)_$($ObjectType)_$($ObjectName).sql"
        $FilePath = Join-Path $OutputFolderPath $FileName
        $scripter.Options.Filename = $FilePath
        $UrnCollection = [Microsoft.SqlServer.Management.Smo.urnCollection]::new()
        $URNCollection.add($item.urn)
        $scripter.script($URNCollection)
    }


}

$Assembly = [System.Reflection.Assembly]::LoadWithPartialName( "Microsoft.SqlServer.SMO")
if ($Assembly.Evidence.version.major -gt 9) {
    $null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended")
}