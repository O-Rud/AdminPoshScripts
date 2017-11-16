Function Connect-ExchangeOnline {
    <#
    .SYNOPSIS
    Establish connection to exchange online
    
    .DESCRIPTION
    Establish connection to exchange online and downloads powershell cmdlets

    .PARAMETER Credential
    PSCredential to be used during connection
    
    .EXAMPLE
    PS> Connect-ExchangeOnline
    
    Will ask for credential and use it to connect to Exchange online services

    #>
    [CmdletBinding()]
    param(
        [pscredential]$Credential = $(Get-Credential)

    )
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri 'https://outlook.office365.com/powershell-liveid/' -Credential $Credential -Authentication Basic -AllowRedirection
    Import-Module (Import-PSSession $Session -AllowClobber) -Global
}

Function ConvertTo-NormalizedPhoneNumber {
    <#
    .SYNOPSIS
    Converts phone number to normalized form
    
    .DESCRIPTION
    Converts phone number to normalized form 
    
    .PARAMETER PhoneNumber
    Phone number to be converted
    
    .PARAMETER LocalPrefix
    Country prefix to add to local numbers
    
    .EXAMPLE
    ConvertTo-NormalizedPhoneNumber 015855555555
    +4915855555555

    .EXAMPLE
    PS> ConvertTo-NormalizedPhoneNumber 004915855555555
    +4915855555555
    
    .EXAMPLE
    PS> ConvertTo-NormalizedPhoneNumber +4915855555555
    +4915855555555
    #>
    [CmdletBinding()]
    param(
        [string]$PhoneNumber,
        [string]$LocalPrefix = "+49"
    )
    if ($PhoneNumber -match "\b\+\d+\b") {return $Phonenumber}
    elseif ($PhoneNumber -match "\b00[1-9]\d+\b") {return "+$($Phonenumber.TrimStart("0"))"}
    elseif ($PhoneNumber -match "\b0[1-9]\d+\b") {return "$LocalPrefix$($Phonenumber.TrimStart("0"))"}
    else {throw "Invalid PhoneNumber $Phonenumber"}
}

Function Get-PlacetelNumbers {
    <#
    .SYNOPSIS
    Get list of numbers provided by PlaceTel
    
    .DESCRIPTION
    Uses PlaceTel API to get list of provided numbers
    
    .PARAMETER ApiKey
    API key used to authenticate at placetel. API key is available at placetel website
    
    .EXAMPLE
    PS> Get-PlacetelNumbers -ApiKey lfjghlksdjhfglksdbfglhoghlkbglsdbfgkldjgfsdhfgsbdnf
    #>
    [CmdletBinding()]
    param(
        [string]$ApiKey
    )
    $PlaceTelApiUri = "https://api.placetel.de/api/"
    $ApiMethod = "getNumbers"
    $OutputFormat = 'json'
    $RequestUri = "$PlaceTelApiUri$ApiMethod.$OutputFormat"
    $result = Invoke-RestMethod -Uri $RequestUri -UseBasicParsing -Method Post -Body "api_key=$ApiKey"
    foreach ($number in $result) {
        ConvertTo-NormalizedPhoneNumber $Number.pstn_number
    }
}

Function Get-LineUriPhoneNumber {
    <#
    .SYNOPSIS
    Extract phone number from phone uri
    
    .DESCRIPTION
    Extract phone number from phone uri. Accepts input from pipeline
    
    .PARAMETER LineUri
    Phone uri string
    
    .EXAMPLE
    PS> Get-LineUriPhoneNumber -LineUri "tel:+4915855555555;ext=555"
    +4915855555555
    
    .EXAMPLE
    PS> Get-csUser contoso\john.doe | Get-LineUriPhoneNumber
    +4915855555555
    #>
    [CmdletBinding()]
    param([parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)][string]$LineUri)
    Begin {
        $regex = [regex]"tel:(\+?[\d]+)"
    }
    process {
        $match = $regex.match($LineUri);
        if ($match.Success) {$match.Groups[1].value}
    }
}

Function Convert-NumberRangeToArray {
    <#
    .SYNOPSIS
    Converts number range boundaries to array of contained numbers
    
    .DESCRIPTION
    Converts number range boundaries to array of contained numbers. Numbers can normalized, non-normalized or phone uri. Output will be in the same format as Starting number
    
    .PARAMETER NumberRangeStart
    First number in range
        
    .PARAMETER NumberRangeEnd
    Last number in range
    
    .EXAMPLE
    PS> Convert-NumberRangeToArray -NumberRangeStart "+4915855555555" -NumberRangeEnd "+4915855555559"
    +4915855555555
    +4915855555556
    +4915855555557
    +4915855555558
    +4915855555559

    .EXAMPLE
    PS > Convert-NumberRangeToArray -NumberRangeStart "tel:+4915855555555" -NumberRangeEnd "tel:+4915855555559"
    tel:+4915855555555
    tel:+4915855555556
    tel:+4915855555557
    tel:+4915855555558
    tel:+4915855555559  
    
    #>
    [CmdletBinding()]
    param(
        [parameter (Mandatory = $true, ValueFromPipelineByPropertyName)][string]$NumberRangeStart,
        [parameter (Mandatory = $true, ValueFromPipelineByPropertyName)][string]$NumberRangeEnd
    )
    Begin {
        $r = [regex]"(tel:)?(\+)?([0]+)?([\d]+)"
    }
    process {
        $mstart = $r.Match($NumberRangeStart)
        $mend = $r.Match($NumberRangeEnd)
        $Prefix = $mstart.groups[1..3] -join ''
        [int64]$start = $mstart.groups[4].value
        [int64]$end = $mend.groups[4].value
        for ([int64]$num = $start; $num -le $end; $num++) {
            "$Prefix$num"
        }

    }
}

Function Get-SfBUsedNumbers {
    <#
    .SYNOPSIS
    Returns list of all numbers used by Skype for Business
    
    .DESCRIPTION
    Returns array of all numbers assigned to user, dial-in numbers or saved as unassigned number
    
    .PARAMETER ExcludeUnassignedNumbers
    If specified Unassigned numbers will not be returned
    
    .EXAMPLE
    Get-SfBUsedNumbers
    
    .NOTES
    General notes
    #>
    [CmdletBinding()]
    param([switch]$ExcludeUnassignedNumbers)
    #User Numbers
    get-csuser -Filter {EnterpriseVoiceEnabled -eq $true} | Get-LineUriPhoneNumber
    #Conference DialIn
    get-CsDialInConferencingAccessNumber | Get-LineUriPhoneNumber
    #Unassigned Numbers
    if (-not $ExcludeUnassignedNumbers) {
        Get-CsUnassignedNumber | Convert-NumberRangeToArray | Get-LineUriPhoneNumber
    }
}

Function Get-FreePhoneNumbers {
    <#
    .SYNOPSIS
    Returns list of not used phone numbers for Skype for Business
    
    .DESCRIPTION
    Returns list of not used phone numbers provided by Placetel, but not used for user, dial-in conferencing or unassigned call forwarding
    
    .PARAMETER PlaceTelApiKey
    API key used to authenticate at placetel. API key is available at placetel website
    
    .EXAMPLE
    Get-FreePhoneNumbers -PlaceTelApiKey asdlfhkadkjsbfkjahsdfkldaslfkgdhjasgflkdasbflasdfghaojdsfjasdg
    #>
    [CmdletBinding()]
    param ([parameter (Mandatory = $true)][string]$PlaceTelApiKey)
    $AllNumbers = Get-PlacetelNumbers -ApiKey $PlaceTelApiKey
    $BusyNumbers = Get-SfBUsedNumbers
    $AllNumbers | Where-Object {$BusyNumbers -notcontains $_}
}

Function Get-SfBWrongNumberConfig {
    <#
    .SYNOPSIS
    Returns Skype for Business users, who has incorrect phone numbers

    .DESCRIPTION
    Returns Skype for Business users, who has incorrect phone numbers (Not available for Skype for business)

    .PARAMETER PlaceTelApiKey
    API key used to authenticate at placetel. API key is available at placetel website

    .EXAMPLE
    Get-SfBWrongNumberConfig -PlaceTelApiKey asdlfhkadkjsbfkjahsdfkldaslfkgdhjasgflkdasbflasdfghaojdsfjasdg
    #>
    [CmdletBinding()]
    param([parameter (Mandatory = $true)][string]$PlaceTelApiKey)
    $AllNumbers = Get-PlacetelNumbers -ApiKey $PlaceTelApiKey
    Get-CsUser -Filter {EnterpriseVoiceEnabled -eq $true} | Where-Object {$AllNumbers -notcontains $($_ | Get-LineUriPhoneNumber)}
}

Function Set-SfBSecondaryNumber {
    <#
    .SYNOPSIS
    Creates secondary number for user
    
    .DESCRIPTION
    Creates unassigned phone number and if required announcement, to forward calls to specified user
    
    .PARAMETER Identity
    Skype for business user identity. Can be
        -- csUser object;
        -- the user's SIP address;
        -- the user's user principal name (UPN);
        -- the user's domain name and logon name, in the form domain\logon (for example, litwareinc\kenmyer);
        -- the user's Active Directory display name (for example, Ken Myer). You can also reference a user account by using the user's Active Directory distinguished name.
    
    .PARAMETER LineUri
    Phone number to be used. The line Uniform Resource Identifier (URI) must be specified using the E.164 format and use the "TEL:" prefix. For example: TEL:+14255551297
    
    .EXAMPLE
    Set-SfBSecondaryNumber -Identity contoso\john.doe -LineUri tel:+4915855555555
    
    .NOTES
    General notes
    #>
    [CmdletBinding()]
    param(
        [parameter (Mandatory = $true, ValueFromPipelineByPropertyName)]$Identity,
        [parameter (Mandatory = $true)][string]$LineUri
    )
    process {
        if ($Identity -is [Microsoft.Rtc.Management.ADConnect.Schema.OCSADUser]) {
            $csuser = $Identity
        }
        else {
            $csuser = Get-CsUser $Identity
        }
        $SipAddress = $csuser.SipAddress
        $RegistrarPool = $csuser.RegistrarPool
        $Announcement = get-CsAnnouncement | Where-Object {$_.TargetUri -eq $SipAddress} | Select-Object -First 1
        if ($Announcement) {$AnnouncementName = $Announcement.Name}
        else {
            $AnnouncementName = "Forwarding to $SipAddress"
            New-CsAnnouncement -Parent "service:ApplicationServer:$RegistrarPool" -Name $AnnouncementName -TargetURI $SipAddress
        }
        New-CsUnassignedNumber -Identity "$LineUri -> $SipAddress" -AnnouncementService "ApplicationServer:$RegistrarPool" -NumberRangeStart $LineUri -NumberRangeEnd $LineUri -AnnouncementName $AnnouncementName
    }
}

function Import-SfBClientLog {
    <#
    .SYNOPSIS
    Parses Skype for Business client log  
    
    .DESCRIPTION
    Imports Skype for business client log file to object array, which is easier to analyse
    
    .PARAMETER Path
    Path to log file
    
    .EXAMPLE
    Import-SfBClientLog c:\admin\sfbmac.log
    #>
    [CmdletBinding()]
    param (
        [string]$Path
    )
    
    begin {
        $regex = [regex]::new('^(\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d\.\d\d\d)\s([a-zA-Z\d]{16})\s([^\s]+)\s([^\s]+)\s([^\s]+)\s((.|\n)*?)(?=(?:^\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d\.\d\d\d\s[a-zA-Z\d]{16})|\z)','Multiline')
    }
    
    process {
        $log = [io.file]::ReadAllText($Path)
        foreach ($match in $regex.matches($log)) {
            [pscustomobject]@{
                date = [datetime]$match.groups[1].value;
                id = $match.groups[2].value;
                Level = $match.groups[3].value;
                Scope = $match.groups[4].value;
                SfBMethod = $match.groups[5].value;
                Message = $match.groups[6].value
            }
        }
    }
}

function Get-SfBSQLData {
    [CmdletBinding()]
    param (
        [parameter (Mandatory=$true)][string]$Query,
        [ValidateSet("rtclocal","lynclocal","rtc")][string]$Instance='rtclocal',
        [string]$Database = 'rtc'
    )
    $hostname = (Get-CsService -CentralManagement).poolfqdn
    $ServerInstance = "$hostname\$Instance"
    write-debug $ServerInstance
    $res = Invoke-SqlCmd -Query $Query -ServerInstance $ServerInstance -Database $Database
    foreach ($item in $res){
        $ht = @{}
        $Props = ($res | Get-Member -MemberType Properties).Name
        foreach ($prop in $Props){
            if ($item.$prop -is [byte[]]){
                $ht[$prop]=[text.encoding]::UTF8.GetString($item.$prop).trim(0)
            } else {
                $ht[$prop]=$item.$prop
            }
        }
        [pscustomobject]$ht
    }    
}