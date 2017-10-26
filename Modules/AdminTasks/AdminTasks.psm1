Function Connect-ExchangeOnline {
    [CmdletBinding()]
    param(
        [pscredential]$Credential = $(Get-Credential)

    )
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri 'https://outlook.office365.com/powershell-liveid/' -Credential $Credential -Authentication Basic -AllowRedirection
    Import-Module (Import-PSSession $Session -AllowClobber) -Global
}

Function ConvertTo-NormalizedPhoneNumber {
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
    [CmdletBinding()]
    param(
        [parameter (Mandatory = $true, ValueFromPipelineByPropertyName)][string]$NumberRangeStart,
        [parameter (Mandatory = $true, ValueFromPipelineByPropertyName)][string]$NumberRangeEnd
    )
    Begin {
        $r = [regex]"(tel:)(\+)?([0]+)?([\d]+)"
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
    [CmdletBinding()]
    param ([parameter (Mandatory = $true)][string]$PlaceTelApiKey)
    $AllNumbers = Get-PlacetelNumbers -ApiKey $PlaceTelApiKey
    $BusyNumbers = Get-SfBUsedNumbers
    $AllNumbers | Where-Object {$BusyNumbers -notcontains $_}
}

Function Get-WrongSfBNumberConfig {
    [CmdletBinding()]
    param([parameter (Mandatory = $true)][string]$PlaceTelApiKey)
    $AllNumbers = Get-PlacetelNumbers -ApiKey $PlaceTelApiKey
    Get-CsUser -Filter {EnterpriseVoiceEnabled -eq $true} | Where-Object {$AllNumbers -notcontains $($_ | Get-LineUriPhoneNumber)}
}

Function Set-SfBSecondaryNumber {
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

function Read-SfBClientLog {
    [CmdletBinding()]
    param (
        [string]$Path
    )
    
    begin {
        $regex = [regex]"(\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d\.\d\d\d)\s([a-zA-Z\d]{16})\s([^\s]+)\s([^\s]+)\s(.+)"
    }
    
    process {
        $log = [io.file]::ReadAllText($Path)
        foreach ($match in $regex.matches($log)) {
            [pscustomobject]@{
                date = [datetime]$match.groups[1].value;
                id = $match.groups[2].value;
                Level = $match.groups[3].value; Scope = $match.groups[4].value;
                Message = $match.groups[5].value
            }
        }
    }
}