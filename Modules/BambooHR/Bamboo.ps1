Import-Module CertEncrypt
[string]$ApiVer = 'v1'
$Subdomain = 'depositsolutions'
$EncryptedApiKey = 'i6t3SNzcVq5GcMdvCsECFQWV8TOARBjySh8tbmj/3e/qxKKlUnkWYWxJaZPdRCjAWNCCCwO/EE3X2GdPPwt55UaMlucgdnEAbq/UEjkPvylZEtRLuqKwUcOMlYta/w2zqLxTPzXQLDu0qnFNftq1jZ7NWdJadTLwz8T6PHp7vfWyt3wkIOD2TQ1eFvHHYT8HRYX/R4PNjnIfdXR9KB4bH9c+76G8mTvzq2I9xFA+IfMEvdg454hNGMFRNxstQefF/owzlsiMZno3XYQOGOoZvgEuWcpUWryQ+r9XSkdpWLnA/ckEOgIND7w6BBqmSdc3z+D2K2+m6l4JaaqyPcsbaA=='
$ApiKey = Get-CertDecryptedString -SourceString $EncryptedApiKey -CertThumbprint 2644DEF38137A8037BE0C1F4B2FF0599607CCECA
$ApiCall = "employees/1?fields=1,2,employeenumber,bestemail,customCitizenship"
$secpasswd = ConvertTo-SecureString "x" -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($ApiKey, $secpasswd)
$uri =  "https://api.bamboohr.com/api/gateway.php/${Subdomain}/${ApiVer}/${ApiCall}"
$uri1 =  "https://api.bamboohr.com/api/gateway.php/${Subdomain}/v2/${ApiCall}"
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$retryNr = 0
Invoke-RestMethod -Method Get -Uri $uri -Credential $mycreds -Headers @{Accept = "application/json"} -ErrorAction SilentlyContinue -ErrorVariable ApiCallError
Invoke-RestMethod -Method Get -Uri $uri1 -Credential $mycreds -Headers @{Accept = "application/json"} -ErrorAction SilentlyContinue -ErrorVariable ApiCallError; Start-Sleep -Milliseconds 100

$ApiCallError



#