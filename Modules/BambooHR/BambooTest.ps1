import-module  BambooHR -Force
Import-Module CertEncrypt

$EncryptedApiKey = 'i6t3SNzcVq5GcMdvCsECFQWV8TOARBjySh8tbmj/3e/qxKKlUnkWYWxJaZPdRCjAWNCCCwO/EE3X2GdPPwt55UaMlucgdnEAbq/UEjkPvylZEtRLuqKwUcOMlYta/w2zqLxTPzXQLDu0qnFNftq1jZ7NWdJadTLwz8T6PHp7vfWyt3wkIOD2TQ1eFvHHYT8HRYX/R4PNjnIfdXR9KB4bH9c+76G8mTvzq2I9xFA+IfMEvdg454hNGMFRNxstQefF/owzlsiMZno3XYQOGOoZvgEuWcpUWryQ+r9XSkdpWLnA/ckEOgIND7w6BBqmSdc3z+D2K2+m6l4JaaqyPcsbaA=='
$ApiKey = Get-CertDecryptedString -SourceString $EncryptedApiKey -CertThumbprint 2644DEF38137A8037BE0C1F4B2FF0599607CCECA
$Subdomain = "depositsolutions"
$PSDefaultParameterValues."*-Bamboo*:ApiKey" = $ApiKey
$PSDefaultParameterValues."*-Bamboo*:Subdomain"=$Subdomain

$DebugPreference = 'Continue'
#$empl = Get-Bamboodirectory | Sort-Object id | Get-BambooEmployee
$fields = Invoke-BambooAPI -ApiCall "meta/fields/" -ApiKey $ApiKey -Subdomain $Subdomain
$prop = $fields | select name, @{n='systemname'; e={if ([string]$($_.alias) -ne ''){$_.alias} else {$_.id}}} | select -ExpandProperty systemname
$FildNames = @{}
$f = $fields | select name, @{n='systemname'; e={if ([string]$($_.alias) -ne ''){$_.alias} else {$_.id}}}
$f | %{$FildNames[[string]($_.systemname)]=$_.name.trim()}
$u = Get-BambooEmployee -id 7 -Properties $prop
$u | gm -MemberType NoteProperty | select name, @{n='DisplayName';e={$FildNames[$_.name]}}, @{n='value';e={$u.$($_.name)}} | Out-GridView