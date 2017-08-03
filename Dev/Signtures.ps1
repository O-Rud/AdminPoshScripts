param(
    [string]$TemplatePath = 'C:\Work\signatur.html',
    [string]$OutputFolder = 'C:\Work\Signatures'
)
$template = get-content $TemplatePath -encoding UTF8
$Userdata = Get-ADUser -filter {enabled -eq $true} -SearchBase "OU=Site,DC=ds,DC=net" -Properties mail, telephoneNumber, mobile, Title | Select-Object Surname, GivenName, Title, telephoneNumber, mobile, mail, samaccountname

foreach ($user in $UserData) {
    $NewFileText  = $template
    $NewFileName = "$($user.samaccountname).htm"
    if ($([string]$user.telephoneNumber).trim() -ne ""){
        $phone = "T: $($user.telephonenumber)<br>"
    } else{
        $phone = ""
    }
    if ($([string]$user.mobile).trim() -ne ""){
        $Mobile = "M: $($user.mobile)<br>"
    } else{
        $Mobile = ""
    }
    $repl = @{
        '%%FirstName%%'   = $user.GivenName
        '%%LastName%%'    = $user.Surname
        '%%title%%'       = $user.title
        '%%TPhoneNumber%%' = $phone
        '%%MPhoneNumber%%' = $Mobile
        '%%Email%%'       = $user.mail
    }
    foreach ($key in $repl.Keys) {
        $NewFileText = $NewFileText.replace($key, $repl[$key])
    }
    $NewFileText | Set-Content -Path $(Join-Path $OutputFolder $NewFileName) -Encoding UTF8
}