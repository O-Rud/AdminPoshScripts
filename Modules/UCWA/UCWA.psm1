
class UCWAApplication {
    [string]$User
    [string]$AppBaseUri
    [string]$UserAgent = 'UCWA Samples'
    [string]$EndpointId = "a917c6f4-976c-4cf3-847d-cdfffa28ccdf"
    [string]$Culture = "en-US"
    [string]$DiscoveryUri
    [object]$Cache
    [object]$DiscoveryCache
    [hashtable]$resources
    hidden[pscredential]$Credential
    
    hidden [string]$AuthHeader
    hidden [object]$AuthToken

    UCWAApp() {
        $This.User = ([adsi]"LDAP://<SID=$([Security.Principal.WindowsIdentity]::GetCurrent().user.value)>")."msRTCSIP-PrimaryUserAddress"
        $This.DiscoveryUri = $This::GetDiscoveryUri($This.User)
    }

    static [string]GetDiscoveryUri([string]$User) {
        $Domain = ($User -split "@")[1]
        $IntDiscover = "LyncDiscoverInternal.$Domain"
        $ExtDiscover = "LyncDiscover.$Domain"
        try {$DiscoveryInfo = Invoke-RestMethod "HTTPS://$IntDiscover" -Method Get}
        catch {$DiscoveryInfo = Invoke-RestMethod "HTTPS://$ExtDiscover" -Method Get}
        if (($DiscoveryInfo._links | Get-Member -MemberType Properties).name -contains 'user') {
            return $DiscoveryInfo._links.user.href
        }
        else {
            throw "Couldn't discover server for user $user"
        }
    }

    hidden static [hashtable]BrowseMethods([object]$obj, $ObjName, $ParentName){
        [hashtable]$result = @{}
        $FieldNames = ($obj | Get-Member -MemberType Properties).Name
        foreach ($name in $FieldNames) {
            $name = $name.trim()
            #Write-host $name
            if ($name -eq 'href') {
                if ($ObjName -eq 'self') {$MethodName = $ParentName}
                else {$MethodName = $ObjName}
                return @{"$MethodName" = $obj.href}
            }
            else {
                if (-not $obj.$Name.gettype().IsSerializable) {
                    if ($name -eq "_links") {
                        $res = [UCWAApplication]::BrowseMethods($obj.$Name, $ObjName, $ParentName)
                    }
                    else {
                        $res = [UCWAApplication]::BrowseMethods($obj.$Name, $name, $ObjName)
                    }
                    foreach($key in $res.Keys){
                        $result[$key]=$res[$key];
                    }
                }
            }
        }
        return $result
    }

    static [hashtable]BrowseMethods([object]$obj){
        return [UCWAApplication]::BrowseMethods($obj,'application','')
    }

    Connect() {
        $rx = [regex]"(http(?:s)?\:\/\/(?:[^\/]+))\/(?:[\S]+)?"
        $This.DiscoveryCache = $This.InvokeUCWARequest('Get', $This.DiscoveryUri).Content | ConvertFrom-Json
        $AppDiscoveryLink = $This.DiscoveryCache._links.applications.href
        $This.AppBaseUri = $rx.Match($AppDiscoveryLink).Groups[1]
        $AppRequestBody = @{
            UserAgent  = $This.UserAgent
            EndpointId = $This.EndpointId
            Culture    = $This.Culture
        }
        $This.Cache = $This.InvokeUCWARequest('Post', $AppDiscoveryLink, $AppRequestBody).Content | ConvertFrom-Json
        $This.resources = [UCWAApplication]::BrowseMethods($This.Cache)
     }

     Disconnect(){
        $This.InvokeUCWARequest('delete',$This.AppCache._links.self.href)
     }

    hidden ProcessError([object]$Err) {
        if ($err.TargetObject -is [net.webrequest]) {
            $Response = $err.Exception.Response
            switch ($Response.StatusCode.value__) {
                401 {
                    $This.RequestAuthToken($Response)
                }
                default {Write-Error -ErrorRecord $Err}
            }
        }
    }
    
    RequestAuthToken([Net.HttpWebResponse]$Response) {
        if ($Response.Headers -contains 'WWW-Authenticate') {
            $AuthHeaderString = $Response.GetResponseHeader('WWW-Authenticate')
            $rx = [regex]'(?:[^=\s]+\s)?([^=\s]+)="([^"]+)",?'
            $AuthHeaderHT = @{}
            $rx.Matches($AuthHeaderString) | ForEach-Object {
                $realm = $_.groups[1].value
                $value = $_.groups[2].value.split(",")
                $AuthHeaderHT[$realm] = $value
            }
            $AuthUri = $AuthHeaderHT.href[0]
            if ($AuthHeaderHT.grant_type -contains 'urn:microsoft.rtc:windows') {
                $This.AuthToken = Invoke-RestMethod -Method Post -ContentType "application/x-www-form-urlencoded;charset=UTF-8" -Uri $AuthUri -UseDefaultCredentials -Body "grant_type=urn:microsoft.rtc:windows"
                $This.AuthHeader = "{0} {1}" -f $This.AuthToken.token_type, $This.AuthToken.access_token
            }
            else {
                throw "Windows Integrated Authentication is not supported"
            }
        }
    }

    RequestAuthToken() {
        try {
            $Response = Invoke-WebRequest $This.DiscoveryUri -Method Get
        }
        catch {
            $Response = $_.Exception.Response
        }
        if ($Response.StatusCode -eq 401) {
            $This.RequestAuthToken($Response)
        }
    }
    
    [pscustomObject]InvokeUCWARequest(
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,
        [string]$Uri,
        [object]$Body,
        [string]$ContentType,
        [int]$RetryCount 
        
    ) {
        if ($Uri -notmatch "^http(s)?://"){
            $Uri = "{0}{1}" -f $This.AppBaseUri,$Uri
        }
        $RequestParam = @{
            Method      = $Method;
            Uri         = $Uri
            ContentType = $ContentType
        }
        if ($ContentType -eq 'application/json' -and $Body -is [hashtable]){
            $Body = ConvertTo-Json $Body
        }
        if ($Body -ne $null) {
            $RequestParam['Body'] = $Body
        }
        $AllowRetry = $true
        while ($RetryCount -gt 0 -and $AllowRetry) {        
            try {
                if ($This.AuthHeader -ne $null) {
                    $RequestParam['Headers'] = @{Authorization = $This.AuthHeader}
                }
                $Res = Invoke-WebRequest @RequestParam
                $AllowRetry = $False
                return $res
            }
            catch {
                $err = $_
                $This.ProcessError($_)
                --$RetryCount
                if ($RetryCount -eq 0) {
                    Write-Error -ErrorRecord $err -RecommendedAction stop
                }
            }
        }
        return $null
    }

    [pscustomObject]InvokeUCWARequest(
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,
        [string]$Uri
    ) {
        [object]$Body = $null
        [string]$ContentType = 'application/json'
        [int]$RetryCount = 3 
        return $This.InvokeUCWARequest($Method, $Uri,  $Body, $ContentType, $RetryCount)
    }

    [pscustomObject]InvokeUCWARequest(
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,
        [string]$Uri,
        [object]$Body
    ) {
        [string]$ContentType = 'application/json'
        [int]$RetryCount = 3 
        return $This.InvokeUCWARequest($Method, $Uri,  $Body, $ContentType, $RetryCount)
    }

    [pscustomObject]InvokeUCWARequest(
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,
        [string]$Uri,
        [object]$Body,
        [string]$ContentType
    ) {
        [int]$RetryCount = 3 
        return $This.InvokeUCWARequest($Method, $Uri,  $Body, $ContentType, $RetryCount)
    }


}
