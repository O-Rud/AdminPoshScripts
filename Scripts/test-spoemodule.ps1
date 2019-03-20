Import-Module SPOExtentions -Force
$Cred = Get-Credential "oleksii.rud@deposit-solutions.com"
$tenant = 'depositsolutions'
$Site = 'BusinessDevelopment'
#$weburl = "https://depositsolutions.sharepoint.com/sites/OfficeIT"

#$resp = Invoke-SPOEApiCall -SiteUri $weburl -Credential $cred -ApiCall files
$resp = Get-SPOERecycleBin -TenantName $tenant -SiteName $Site -Credential $Cred
$resp