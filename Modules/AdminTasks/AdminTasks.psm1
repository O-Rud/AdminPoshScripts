Function Connect-ExchangeOnline{
    param(
    [pscredential]$Credential = $(Get-Credential)

    )
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri 'https://outlook.office365.com/powershell-liveid/' -Credential $Credential -Authentication Basic -AllowRedirection
    Import-Module (Import-PSSession $Session -AllowClobber) -Global
}

Function ConvertTo-NormalizedPhoneNumber{
param(
    [string]$PhoneNumber,
    [string]$LocalPrefix = "+49"
    )
    if ($PhoneNumber -match "\b\+\d+\b") {return $Phonenumber}
    elseif ($PhoneNumber -match "\b00[1-9]\d+\b") {return "+$($Phonenumber.TrimStart("0"))"}
    elseif ($PhoneNumber -match "\b0[1-9]\d+\b") {return "$LocalPrefix$($Phonenumber.TrimStart("0"))"}
    else {throw "Invalid PhoneNumber $Phonenumber"}
}

Function Get-PlacetelNumbers{
    param(
        [string]$ApiKey
    )
    $PlaceTelApiUri = "https://api.placetel.de/api/"
    $ApiMethod = "getNumbers"
    $OutputFormat = 'json'
    $RequestUri = "$PlaceTelApiUri$ApiMethod.$OutputFormat"
    $result = Invoke-RestMethod -Uri $RequestUri -UseBasicParsing -Method Post -Body "api_key=$ApiKey"
    foreach ($number in $result){
        ConvertTo-NormalizedPhoneNumber $Number.pstn_number
    }
}

Function Get-FreePhoneNumbers
{
    param ([parameter (Mandatory=$true)][string]$PlaceTelApiKey)
    $AllNumbers = Get-PlacetelNumbers -ApiKey $PlaceTelApiKey
    $BusyNumbers = get-csuser -Filter {EnterpriseVoiceEnabled -eq $true} | ForEach-Object{($_.lineuri.split(';') -like "tel:*") -replace('tel:','')}
    $AllNumbers | ?{$BusyNumbers -notcontains $_}
}