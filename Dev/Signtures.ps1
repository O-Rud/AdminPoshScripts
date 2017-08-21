param(
    [string]$htmTemplatePath = '\\ds.net\share\PrgData\Signatures\template\signatur.html',
    [string]$txtTemplatePath = '\\ds.net\share\PrgData\Signatures\template\signatur.txt',
    [string]$OutputFolder = '\\ds.net\share\PrgData\Signatures'
)
$htmtemplate = get-content $htmTemplatePath -encoding UTF8
$txttemplate = [io.file]::ReadAllText($txtTemplatePath,[text.encoding]::UTF8)
$Userdata = Get-ADUser -filter {enabled -eq $true} -SearchBase "OU=Site,DC=ds,DC=net" -Properties mail, telephoneNumber, mobile, Title | Select-Object Surname, GivenName, Title, telephoneNumber, mobile, mail, samaccountname
$regex = [regex]"(%%)([^%]+)(%%)"
foreach ($user in $UserData) {
    $Replacer = {
        param(
            [System.Text.RegularExpressions.Match]$match
        )
        $tag = $match.Value
        $TagName = $tag.Trim("%")
        [string]$($repl.$TagName)
        }
    $NewhtmFileName = "$($user.samaccountname).htm"
    $NewTxtFileName = "$($user.samaccountname).txt"
    if ($([string]$user.telephoneNumber).trim() -ne ""){
        $phone = "T: $($user.telephonenumber)<br>"
        $phonetext = "T: $($user.telephonenumber)`r`n"
    } else{
        $phone = ""
        $phonetext = ""
    }
    if ($([string]$user.mobile).trim() -ne ""){
        $Mobile = "M: $($user.mobile)<br>"
        $Mobiletext = "M: $($user.mobile)`r`n"
    } else{
        $Mobile = ""
        $Mobiletext = ""
    }
    $script:repl = @{
        'FirstName'   = $user.GivenName
        'LastName'    = $user.Surname
        'title'       = $user.title
        'TPhoneNumber' = $phone
        'MPhoneNumber' = $Mobile
        'PhoneNumber' = $phonetext
        'MobileNumber' = $Mobiletext
        'Email'       = $user.mail
    }
    $NewFilehtm = $regex.Replace($htmtemplate, $Replacer)
    $NewFilehtm | Set-Content -Path $(Join-Path $OutputFolder $NewhtmFileName) -Encoding UTF8
    $NewFiletxt = $regex.Replace($txttemplate, $Replacer)
    $NewFiletxt | Set-Content -Path $(Join-Path $OutputFolder $NewTxtFileName) -Encoding UTF8
}
