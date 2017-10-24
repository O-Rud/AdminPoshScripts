Function Connect-ExchangeOnline {
    param(
        [pscredential]$Credential = $(Get-Credential)

    )
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri 'https://outlook.office365.com/powershell-liveid/' -Credential $Credential -Authentication Basic -AllowRedirection
    Import-Module (Import-PSSession $Session -AllowClobber) -Global
}

Function ConvertTo-NormalizedPhoneNumber {
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

Function Get-LineUriPhoneNumber{
    param([parameter(ValueFromPipelineByPropertyName)][string]$LineUri)
    Begin{
        $regex = [regex]"tel:(\+?[\d]+)"
    }
    process{
        $match = $regex.match($LineUri);
        if ($match.Success) {$match.Groups[1].value}
    }
}

Function Get-SfBUsedNumbers{
    #User Numbers
    get-csuser -Filter {EnterpriseVoiceEnabled -eq $true} | Get-LineUriPhoneNumber
    #Conference DialIn
    get-CsDialInConferencingAccessNumber | Get-LineUriPhoneNumber
    }

Function Get-FreePhoneNumbers {
    param ([parameter (Mandatory = $true)][string]$PlaceTelApiKey)
    $AllNumbers = Get-PlacetelNumbers -ApiKey $PlaceTelApiKey
    $BusyNumbers = Get-SfBUsedNumbers
    $AllNumbers | Where-Object {$BusyNumbers -notcontains $_}
}

Function Get-WrongSfBNumberConfig{
    param([parameter (Mandatory = $true)][string]$PlaceTelApiKey)
    $AllNumbers = Get-PlacetelNumbers -ApiKey $PlaceTelApiKey
    Get-CsUser -Filter {EnterpriseVoiceEnabled -eq $true} | Where-Object{$AllNumbers -notcontains $($_ | Get-LineUriPhoneNumber)}
}