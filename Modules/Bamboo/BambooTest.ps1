import-module  .\Bamboo.psm1 -Force

$PSDefaultParameterValues."*-Bamboo*:Subdomain"="depositsolutions"
$PSDefaultParameterValues."*-Bamboo*:ApiKey" = "26d97be6db951d418ad0e46cc10b4b7714090ffd"

$DebugPreference = 'Continue'
#$empl = Get-Bamboodirectory | Sort-Object id | Get-BambooEmployee
$fields = Invoke-BambooAPI -ApiCall "meta/fields/" -ApiKey 26d97be6db951d418ad0e46cc10b4b7714090ffd -Subdomain depositsolutions
$prop = $fields | select name, @{n='systemname'; e={if ([string]$($_.alias) -ne ''){$_.alias} else {$_.id}}} | select -ExpandProperty systemname
$FildNames = @{}
$f = $fields | select name, @{n='systemname'; e={if ([string]$($_.alias) -ne ''){$_.alias} else {$_.id}}}
$f | %{$FildNames[[string]($_.systemname)]=$_.name.trim()}
$u = Get-BambooEmployee -id 1 -Properties $prop
$u | gm -MemberType NoteProperty | select name, @{n='DisplayName';e={$FildNames[$_.name]}}, @{n='value';e={$u.$($_.name)}} | Out-GridView