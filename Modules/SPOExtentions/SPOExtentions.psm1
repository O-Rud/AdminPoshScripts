#Requires -Version 5
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client")
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client.Runtime")
function Get-SPOECredentials {
    [CmdletBinding()]
    param (
        [pscredential]$Credential = $(Get-credential)
    )
    return New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($Credential.UserName, $Credential.Password)   
}

function Get-SPOERecycleBin {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$TenantName,
        [parameter(Mandatory=$true)][string]$SiteName,
        [pscredential]$Credential
    )
    $SPO_Credentials = Get-SPOECredentials -Credential $Credential
    $SiteUri = "https://$TenantName.sharepoint.com/sites/$SiteName"
    $SPO_Context = New-Object Microsoft.SharePoint.Client.ClientContext($SiteUri)
    $SPO_Context.Credentials = $SPO_Credentials
    $SPO_Site = $SPO_Context.Site
    $SPO_RecycleBin = $SPO_Site.RecycleBin
    $SPO_Context.Load($SPO_RecycleBin)
    $SPO_Context.ExecuteQuery()
    return $SPO_RecycleBin
}

function Invoke-SPOEApiCall {
    [CmdletBinding(DefaultParameterSetName='SPOCred_Uri')]
    param (
        [parameter (ParameterSetName='Combined', Mandatory=$true)]
        [string]$TenantName,

        [parameter (ParameterSetName='Combined', Mandatory=$true)]
        [string]$SiteName,
        
        [parameter (ParameterSetName='Uri', Mandatory=$true)]
        [string]$SiteUri,

        [parameter (ParameterSetName='Combined')]
        [parameter (ParameterSetName='Uri')]
        [string]$ApiCall,
        
        [parameter (ParameterSetName='Combined')]
        [parameter (ParameterSetName='Uri')]
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = 'Get',

        [parameter (ParameterSetName='Combined')]
        [parameter (ParameterSetName='Uri')]
        [pscredential]$Credential
    )
    
    if($PSCmdlet.ParameterSetName -eq 'Uri'){
        $regex = [regex]"(https?:\/\/)?([\da-z-]+)\.sharepoint\.com([\/\w \.-]*)*\/?"
        $match = $regex.match($SiteUri)
        if ($match.Success) {
            $TenantName = $match.groups[2].value
        }
    } else {
        $SiteUri = "https://$TenantName.sharepoint.com/sites/$SiteName"
    }

    $SPOCredential = Get-SPOECredentials -TenantName $TenantName -Credential $Credential
    $APIUri = "$($SiteUri.TrimEnd('/'))/_api/$ApiCall"
    $request = [System.Net.WebRequest]::Create($APIUri)
    $request.Credentials = $SPOCredential
    $request.Headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")
    $request.Accept = "application/json;odata=verbose"
    $request.Method=$Method
    $response = $request.GetResponse()
    $ResponseStream = $response.GetResponseStream()
    $StreamReader = [System.IO.StreamReader]::New($ResponseStream)
    $Data=$StreamReader.ReadToEnd() | ConvertFrom-Json
    Return $Data
}

function Publish-SPOEFile {
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline = $true,ValueFromPipelineByPropertyName=$true)][Alias('fullname')][string]$Path,
        [parameter(Mandatory=$true)][string]$TenantName,
        [parameter(Mandatory=$true)][string]$SiteName,
        [parameter(Mandatory=$true)][string]$LibararyName,
        [pscredential]$Credential
    )
    
    begin {
        $SPO_Credentials = Get-SPOECredentials -Credential $Credential
        $SiteUri = "https://$TenantName.sharepoint.com/sites/$SiteName"
        $SPO_Context = New-Object Microsoft.SharePoint.Client.ClientContext($SiteUri)
        $SPO_Context.Credentials = $SPO_Credentials
        $SPO_Site_Lists = $SPO_Context.Web.Lists
        $SPO_Context.Load($SPO_Site_Lists)
        $SPO_Context.ExecuteQuery()
        $SPO_List = $SPO_Site_Lists | Where-object {$_.title -eq $DocLibName}
    }
    
    process {
        $FileStream = New-object IO.FileStream($Path, [System.IO.FileMode]::Open)
        $SPO_FileCreationInfo = New-Object Microsoft.SharePoint.Client.FileCreationInformation
        $SPO_FileCreationInfo.Overwrite = $true
        $SPO_FileCreationInfo.ContentStream = $FileStream
        $SPO_FileCreationInfo.Url = [System.IO.Path]::GetFileName($path)
        $SPO_UploadFile = $SPO_List.RootFolder.Files.Add($SPO_FileCreationInfo)  
        $SPO_Context.Load($SPO_UploadFile)
        $SPO_Context.ExecuteQuery()
    }
    
    end {
    }
}