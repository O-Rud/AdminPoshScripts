ipmo activedirectory
Get-ADUser -filter {enabled -eq $true -and telephoneNumber -like "*"} -properties telephonenumber, department, displayname | select DisplayName, Department, telephonenumber | Out-GridView -Wait
