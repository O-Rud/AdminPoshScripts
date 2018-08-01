param(
    [string]$path
)
$Content = [io.file]::ReadAllText($path)
$PolRegex = [regex]"(?ms)(?<=config firewall policy)(.*?)(?=[\n][\s]*end)"
$RuleRegex = [regex]"(?ms)(?<=edit) ([\d]+)(.*?)(?=[\n][\s]*next)"
$detailsRegex = [regex]"(?<=set) ([\S]+)[\s]+(([\S]+)[\s]?)+"
$PoliciesText = $PolRegex.Match($Content).Value
$RuleMatches = $RuleRegex.Matches($PoliciesText)
foreach($match in $RuleMatches){
    $RuleText = $match.Groups[2].Value
    $DetMatches = $detailsRegex.Matches($RuleText)
    $props = [ordered]@{
        RuleNumber = $match.Groups[1].Value
    }
    $DetMatches | ForEach-Object{
        $props[$_.Groups[1].value] = $_.Groups[3].captures.value.trim('`"')
    }
    [pscustomobject]$props
}