Param(
    [bool]$EnableTLS1_2_Server = $true,
    [bool]$EnableTLS1_2_Client = $true,
    [bool]$DisableTLS1_0 = $true,
    [bool]$DisableTLS1_1_Server = $false,
    [bool]$DisableTLS1_1_Client = $true
)

$SChannelRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
$RegPath1 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319"
New-ItemProperty -path $RegPath1 -name SystemDefaultTlsVersions -value 1 -PropertyType DWORD
New-ItemProperty -path $RegPath1 -name SchUseStrongCrypto -value 1 -PropertyType DWORD

$RegPath2 = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319"
New-ItemProperty -path $RegPath2 -name SystemDefaultTlsVersions -value 1 -PropertyType DWORD
New-ItemProperty -path $RegPath2 -name SchUseStrongCrypto -value 1 -PropertyType DWORD

if ($EnableTLS1_2_Server){
    New-Item $SChannelRegPath"\TLS 1.2\Server" -Force
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.2\Server" -Name Enabled -Value 1 -PropertyType DWORD
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.2\Server" -Name DisabledByDefault -Value 0 -PropertyType DWORD
}
if ($EnableTLS1_2_Client){
    New-Item $SChannelRegPath"\TLS 1.2\Client" -Force
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.2\Client" -Name Enabled -Value 1 -PropertyType DWORD
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.2\Client" -Name DisabledByDefault -Value 0 -PropertyType DWORD
}


if ($DisableTLS1_0){
    New-Item $SChannelRegPath"\TLS 1.0\Server" -Force
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.0\SERVER" -Name Enabled -Value 0 -PropertyType DWORD
    New-Item $SChannelRegPath"\TLS 1.0\Client" -Force
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.0\Client" -Name Enabled -Value 0 -PropertyType DWORD
}

if ($DisableTLS1_1_Server){
    New-Item $SChannelRegPath"\TLS 1.1\Server" -force
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.1\Server" -Name Enabled -Value 0 -PropertyType DWORD
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.1\Server" -Name DisabledByDefault -Value 0 -PropertyType DWORD
}

if ($DisableTLS1_1_Client){
    New-Item $SChannelRegPath"\TLS 1.1\Client" -force
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.1\Client" -Name Enabled -Value 0 -PropertyType DWORD
    New-ItemProperty -Path $SChannelRegPath"\TLS 1.1\Client" -Name DisabledByDefault -Value 0 -PropertyType DWORD
}