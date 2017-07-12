
[string]$ApiVer = 'v1'
$Subdomain = 'depositsolutions'
$ApiKey = "26d97be6db951d418ad0e46cc10b4b7714090ffd"
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