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
    [CmdletBinding(DefaultParameterSetName='SPOCred')]
    param (
        [parameter(Mandatory=$true)][string]$TenantName,
        [parameter(Mandatory=$true)][string]$SiteName,
        [pscredential]$Credential
    )
    $SPOCredentials = Get-SPOECredentials -TenantName $TenantName -Credential $Credential
    $SiteUri = "https://$TenantName.sharepoint.com/sites/$SiteName"
    $SPOContext = New-Object Microsoft.SharePoint.Client.ClientContext($SiteUri)
    $SPOContext.Credentials = $SPOCredentials
    $SPOSite = $SPOContext.Site
    $SPORecycleBin = $spoSite.RecycleBin
    $SPOContext.Load($SPORecycleBin)
    $SPOContext.ExecuteQuery()
    return $SPORecycleBin
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