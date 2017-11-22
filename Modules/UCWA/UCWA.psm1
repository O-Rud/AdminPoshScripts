using namespace System.Web

enum audioPreference{
    VoipAudio
    PhoneAudio
}

enum Availability{
    Away
    BeRightBack
    Busy
    DoNotDisturb
    Offwork
    Online
}

class UCWAApplication {
    [string]$User
    [string]$AppBaseUri
    [string]$UserAgent = 'UCWA Samples'
    [string]$EndpointId = "a917c6f4-976c-4cf3-847d-cdfffa28ccdf"
    [string]$Culture = "en-US"
    [string]$DiscoveryUri
    [string]$EventsUri
    [collections.arraylist]$Events = @()
    [collections.arraylist]$Meetings = @()
    [collections.arraylist]$Conversations = @()
    [object]$Cache
    [object]$DiscoveryCache
    [hashtable]$Resources
    [pscredential]$Credential
    hidden [string]$AuthHeader
    hidden [object]$AuthToken

    hidden Init($User) {
        $this.User = $User
        $this.DiscoveryUri = $This::GetDiscoveryUri($this.User)
    }

    UCWAApplication([string]$User) {
        Init($user)
    }

    UCWAApplication() {
        $this.Init(([adsi]"LDAP://<SID=$([Security.Principal.WindowsIdentity]::GetCurrent().user.value)>")."msRTCSIP-PrimaryUserAddress")
    }

    UCWAApplication([string]$User, [pscredential]$Credential) {
        $this.Credential = $Credential
        $this.Init($User)
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

    hidden static [hashtable]BrowseMethods([object]$obj, $ObjName, $ParentName) {
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
                    foreach ($key in $res.Keys) {
                        $result[$key] = $res[$key];
                    }
                }
            }
        }
        return $result
    }

    static [hashtable]BrowseMethods([object]$obj) {
        return [UCWAApplication]::BrowseMethods($obj, 'application', '')
    }

    Connect() {
        $rx = [regex]"(http(?:s)?\:\/\/(?:[^\/]+))\/(?:[\S]+)?"
        $Responce = $this.InvokeUCWARequest('Get', $this.DiscoveryUri)
        $this.DiscoveryCache = $Responce.Data
        $AppDiscoveryLink = $this.DiscoveryCache._links.applications.href
        $this.AppBaseUri = $rx.Match($AppDiscoveryLink).Groups[1]
        $AppRequestBody = @{
            UserAgent  = $this.UserAgent
            EndpointId = $this.EndpointId
            Culture    = $this.Culture
        }
        $Responce = $this.InvokeUCWARequest('Post', $AppDiscoveryLink, $AppRequestBody)
        $this.Cache = $Responce.Data
        $this.resources = [UCWAApplication]::BrowseMethods($this.Cache)
        $this.User = $this.Cache._embedded.me.Uri
        $this.EventsUri = $this.Cache._links.events.href
    }

    Update(){
        $Responce = $this.InvokeUCWARequest('Get', $this.Resources.application)
        $this.Cache = $Responce.Data
        $this.resources = [UCWAApplication]::BrowseMethods($this.Cache)
    }

    Disconnect() {
        $this.InvokeUCWARequest('delete', $this.Resources.application)
    }

    makeMeAvailable(){
        $this.Update()
        if ($this.Resources.makeMeAvailable){
            $RequestData = @{signInAs='DoNotDisturb'; supportedMessageFormats=@('Plain','Html'); supportedModalities=@("Messaging","PhoneAudio"); phoneNumber="55555555"}
            $this.InvokeUCWARequest('POST',$this.Resources.makeMeAvailable,$RequestData)
        }
    }

    reportMyActivity(){
        $this.Update()
        if ($this.Resources.reportMyActivity){
            $this.InvokeUCWARequest('Post',$this.Resources.reportMyActivity)
        } else {
            $this.makeMeAvailable()
            $this.Update()
            $this.InvokeUCWARequest('Post',$this.Resources.reportMyActivity)
        }
    }

    hidden [bool]ProcessError([object]$Err) {
        $res = $true
        if ($err.TargetObject -is [net.webrequest]) {
            $Response = $err.Exception.Response
            switch ($Response.StatusCode.value__) {
                401 {
                    $this.RequestAuthToken($Response)
                }
                {$_ -gt 401 -and $_ -lt 500} {
                    Write-Error -ErrorRecord $Err
                    $res =  $false
                }
                {$_ -ge 500 -and $_ -lt 600} {
                    Write-Error -ErrorRecord $Err
                    Start-Sleep -Seconds 3
                }
                default {
                    Write-Error -ErrorRecord $Err
                }
            }
        }
        else {
            Write-Error -ErrorRecord $Err
        }
        return $res
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
            If ($this.Credential -ne $null) {
                $Username = [System.Web.HttpUtility]::UrlEncode($this.Credential.UserName)
                $Pswd = [System.Web.HttpUtility]::UrlEncode($this.Credential.GetNetworkCredential().Password)
                $AuthRequestBody = "grant_type=password&username={0}&password={1}" -f $Username, $Pswd
            }
            elseif ($AuthHeaderHT.grant_type -contains 'urn:microsoft.rtc:windows') {
                $AuthRequestBody = "grant_type=urn:microsoft.rtc:windows"
            }
            else {
                throw "No credentials provided and Windows Integrated Authentication is not supported"
            }
            $this.AuthToken = Invoke-RestMethod -Method Post -ContentType "application/x-www-form-urlencoded;charset=UTF-8" -Uri $AuthUri -UseDefaultCredentials -Body $AuthRequestBody
            $this.AuthHeader = "{0} {1}" -f $this.AuthToken.token_type, $this.AuthToken.access_token
        }
    }


    RequestAuthToken() {
        try {
            $Response = Invoke-WebRequest $this.DiscoveryUri -Method Get
        }
        catch {
            $Response = $_.Exception.Response
        }
        if ($Response.StatusCode -eq 401) {
            $this.RequestAuthToken($Response)
        }
    }
    
    [pscustomObject]InvokeUCWARequest(
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,
        [string]$Uri,
        [object]$Body,
        [string]$ContentType,
        [int]$RetryCount 
        
    ) {
        if ($Uri -notmatch "^http(s)?://") {
            $Uri = "{0}{1}" -f $this.AppBaseUri, $Uri
        }
        $RequestParam = @{
            Method      = $Method;
            Uri         = $Uri
            ContentType = $ContentType
        }
        if ($ContentType -eq 'application/json' -and $Body -is [hashtable]) {
            $Body = ConvertTo-Json $Body
        }
        if ($Body -ne $null) {
            $RequestParam['Body'] = $Body
        }
        $AllowRetry = $true
        while ($RetryCount -gt 0 -and $AllowRetry) {        
            try {
                if ($this.AuthHeader -ne $null) {
                    $RequestParam['Headers'] = @{Authorization = $this.AuthHeader}
                }
                $Res = Invoke-WebRequest @RequestParam
                $AllowRetry = $False
                if ($Res.Headers.'Content-Type' -match 'application/json' -and $res.RawContentLength -gt 0) {
                    $Data = convertfrom-json $res.Content
                }
                else {
                    $Data = $res.Content
                }
                return [pscustomobject]@{
                    'Data'    = $Data
                    'Headers' = $res.Headers
                }

            }
            catch {
                $err = $_
                $AllowRetry = $this.ProcessError($_)
                --$RetryCount
                if ($RetryCount -eq 0 -or $AllowRetry -eq $false) {
                    Write-Error -ErrorRecord $err -ErrorAction stop
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
        [int]$RetryCount = 5
        return $this.InvokeUCWARequest($Method, $Uri, $Body, $ContentType, $RetryCount)
    }

    [pscustomObject]InvokeUCWARequest(
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,
        [string]$Uri,
        [object]$Body
    ) {
        [string]$ContentType = 'application/json'
        [int]$RetryCount = 5
        return $this.InvokeUCWARequest($Method, $Uri, $Body, $ContentType, $RetryCount)
    }

    [pscustomObject]InvokeUCWARequest(
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,
        [string]$Uri,
        [object]$Body,
        [string]$ContentType
    ) {
        [int]$RetryCount = 5
        return $this.InvokeUCWARequest($Method, $Uri, $Body, $ContentType, $RetryCount)
    }

    joinOnlineMeeting([string]$MeetingJoinUrl) {
        $res = Invoke-WebRequest -Uri $MeetingJoinUrl -Headers @{Accept = 'Application/vnd.microsoft.lync.meeting+xml'} -ErrorAction Stop
        $Data = [xml]$res.Content
        $onlineMeetingUri = $data.'conf-info'.'conf-uri'
        $OperationId = [guid]::NewGuid().guid
        $JoinRequet = @{
            onlineMeetingUri = $onlineMeetingUri
            operationId      = $OperationId
            importance       = 'Normal'
        }
        $result = $this.InvokeUCWARequest('Post', $this.Resources.joinOnlineMeeting, $JoinRequet)
        $this.queryUCWAEvents()
        $this.Conversations | ForEach-Object{$_.EnableMessaging()}

    }

    queryUCWAEvents() {
        $Data = $this.InvokeUCWARequest('Get', $this.EventsUri).Data
        $this.EventsUri = $Data._links.next.href
        foreach ($sender in $Data.sender) {
            foreach ($evt in $sender.events) {
                $Event = [UCWAEvent]::new()
                $Event.Sender = $sender.rel
                $Event.SenderUri = $sender.href
                $Event.Type = $evt.type
                $Event.ItemType = $evt.link.rel
                $Event.ItemUri = $evt.link.href
                $Event.ItemObject = $evt._embedded.$($Event.ItemType)
                $RelatedObjNames = ($evt |  Get-Member -MemberType Properties).name
                foreach ($name in $RelatedObjNames) {
                    if (('link', 'type', '_embedded') -notcontains $name) {
                        $Event.RelatedObjects[$name] = $evt.name
                    }
                }
                $this.Events.Add($Event)
            }
        }
        $this.processUCWAEvents()
    }

    processUCWAEvents() {
        [collections.arraylist]$ToRemove = @()
        foreach ($Event in $this.Events) {
            switch ($Event.ItemType) {
                'conversation' {
                    $Conv = $null
                    $Conv = $this.Conversations | Where-Object {$_.ConversationUri -eq $Event.ItemObject._links.self.href}
                    if ($Conv) {
                        $Conv.Update($Event.ItemObject)
                    }
                    else {
                        if ($Event.ItemObject -ne $null) {
                            $this.Conversations.Add([UCWAConversation]::new($This, $Event.ItemObject))
                        }
                    }
                } 
                'onlineMeeting' {

                }
            }
            $ToRemove.add($Event)
        }
        foreach ($Item in $ToRemove) {
            $this.Events.Remove($Item)
        }
    }

    keepAlive() {
        while ($true) {
            $this.queryUCWAEvents()
            $this.Conversations.ToArray() | ForEach-Object {$_.update()}
            $this.reportMyActivity()
            Write-host
            Write-Host $this.EventsUri
            Write-host
            Write-Host $this.Conversations
        }
    }

}

class UCWAMeeting {
    [UCWAApplication]$ParentApp
    [string]$MeetingUri
    [string]$onlineMeetingUri
    [string]$organizerUri
    [string]$organizerName
    [string]$disclaimerBody
    [string]$disclaimerTitle
    [string]$hostingNetwork
    [string]$largeMeeting
    [string]$joinUrl
    [string]$ConversationLink
    [hashtable]$Resources
    [datetime]$MeetingEnd

    UCWAMeeting([UCWAApplication]$ParentApp, [object]$UCWAResponce) {
        $this.ParentApp = $ParentApp
        $this.MeetingUri = $UCWAResponce._links.self.href
        $this.Update($UCWAResponce)
    }

    Update([object]$UCWAResponce){
        $this.onlineMeetingUri = $UCWAResponce.onlineMeetingUri
        $this.organizerUri = $UCWAResponce.organizerUri
        $this.organizerName = $UCWAResponce.organizerName
        $this.disclaimerBody = $UCWAResponce.disclaimerBody
        $this.disclaimerTitle = $UCWAResponce.disclaimerTitle
        $this.hostingNetwork = $UCWAResponce.hostingNetwork
        $this.largeMeeting = $UCWAResponce.largeMeeting
        $this.joinUrl = $UCWAResponce.joinUrl
        $this.ConversationLink = $UCWAResponce._links.conversation.href
        $this.Resources = @{}
        ($UCWAResponce._links | Get-Member -MemberType Properties).Name | ForEach-Object {$this.Resources[$_] = $UCWAResponce._links.$_.href}
    }

}

class UCWAConversation {
    [UCWAApplication]$ParentApp
    [string]$ConversationUri
    [string]$State
    [string]$threadId
    [string]$subject
    [int]$participantCount
    [object]$Messaging
    [string]$OnlineMeetingJoinUrl
    [hashtable]$Resources

    UCWAConversation([UCWAApplication]$ParentApp, [object]$UCWAResponce) {
        $this.ParentApp = $ParentApp
        $this.ConversationUri = $UCWAResponce._links.self.href
        $this.Update($UCWAResponce)
    }
    
    UCWAConversation([UCWAApplication]$ParentApp, [string]$Uri) {
        $this.ParentApp = $ParentApp
        $this.ConversationUri = $Uri
        $this.Update()
    }
    
    Update([object]$UCWAResponce) {
        if ($UCWAResponce._links.self.href -ne $this.ConversationUri) {
            throw "Conversation Uri mismatch ($($UCWAResponce._links.self.href) != $($this.ConversationUri))"
        }
        else {
            $this.State = $UCWAResponce.State
            $this.threadId = $UCWAResponce.threadId
            $this.subject = $UCWAResponce.subject
            $this.participantCount = $UCWAResponce.participantCount
            $this.Resources = @{}
            ($UCWAResponce._links | Get-Member -MemberType Properties).Name | ForEach-Object {$this.Resources[$_] = $UCWAResponce._links.$_.href}
        }
    }

    Update() {
        try{
        $UCWAResponce = $this.ParentApp.InvokeUCWARequest('get', $this.ConversationUri).data
        $this.Update($UCWAResponce)
        $this.Messaging = $this.ParentApp.InvokeUCWARequest('Get',$this.Resources.Messaging).Data
        If ($this.Resources.ContainsKey('onlineMeeting')){
            $OnlineMeeting = $this.ParentApp.InvokeUCWARequest('get',$this.Resources.onlineMeeting).data
            $This.OnlineMeetingJoinUrl = $OnlineMeeting.JoinUrl
        }
        }catch{
            if ($_.Exception.Response.StatusCode.value__ -eq 404){
                $this.ParentApp.Conversations.Remove($This)
            }
        }
        
    }

    Close(){
        $this.ParentApp.InvokeUCWARequest('Delete',$this.ConversationUri)
        $this.ParentApp.Conversations.Remove($This)
    }

    EnableMessaging(){
        $this.Update()
        $Uri = $this.Messaging._links.addMessaging.href
        if ($Uri){
            $this.ParentApp.InvokeUCWARequest('Post',$Uri, @{operationId= [guid]::NewGuid().guid})
        }
    }

    [string]ToString() {
        return $($This | Select-Object ConversationUri, State, threadId, subject, participantCount | ConvertTo-Json)
    }

}

Class UCWAEvent {
    [string]$Sender
    [string]$SenderUri
    [string]$Type
    [string]$ItemType
    [string]$ItemUri
    [Object]$ItemObject
    [hashtable]$RelatedObjects = @{}
}