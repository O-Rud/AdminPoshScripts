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

Function Export-SQLDatabaseScripts{
    param(
        [parameter (Mandatory = $true)][string]$Server,
        [parameter (Mandatory = $true)][string]$Database,
        [parameter (Mandatory = $true)]$Path
    )
    
    set-psdebug -strict
    $ErrorActionPreference = "stop" 
    $Assembly = [System.Reflection.Assembly]::LoadWithPartialName( "Microsoft.SqlServer.SMO")
    if ($Assembly.Evidence.version.major -gt 9) {
        $null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended")
    }
    
    $SQLServer = [Microsoft.SqlServer.Management.Smo.Server]::new($Server)
    if ($SQLServer.Version -eq  $null ){Throw "Can't find the instance $Server"}
    $db = $SQLServer.Databases[$Database] 
    if ($db.name -ne $Database){Throw "Can't find the database '$Database' in $Server"};
    $Filename = "$($Database)_Build.sql"
    if (-not $(Test-path $path)) {mkdir $path}
    $CreationScriptOptions = [Microsoft.SqlServer.Management.SMO.ScriptingOptions]::New()
    $CreationScriptOptions.ExtendedProperties= $true
    $CreationScriptOptions.DRIAll= $true
    $CreationScriptOptions.Indexes= $true
    $CreationScriptOptions.Triggers= $true
    $CreationScriptOptions.ScriptBatchTerminator = $true
    $CreationScriptOptions.IncludeHeaders = $true;
    $CreationScriptOptions.ToFileOnly = $true
    $CreationScriptOptions.IncludeIfNotExists = $true
    $CreationScriptOptions.Filename = Join-Path $Path $FileName;
    $transfer = [Microsoft.SqlServer.Management.Smo.Transfer]::new($db)
    $transfer.Options = $CreationScriptOptions
    $transfer.ScriptTransfer() 
}