$Session = New-Object -ComObject Microsoft.Update.Session
$Searcher = $Session.CreateUpdateSearcher()
$HistoryCount = $Searcher.GetTotalHistoryCount()
# http://msdn.microsoft.com/en-us/library/windows/desktop/aa386532%28v=vs.85%29.aspx
$Searcher.QueryHistory(0, $HistoryCount) | where-object {$_.title -ne $null -or $_.resultcode -ne $null}| ForEach-Object -Process {
    $Title = $_.Title
    $KB = [regex]::Match($_.title, "KB\d{6,7}").value
    # http://msdn.microsoft.com/en-us/library/windows/desktop/aa387095%28v=vs.85%29.aspx
    $Result = $null
    Switch ($_.ResultCode) {
        0 { $Result = 'NotStarted'}
        1 { $Result = 'InProgress' }
        2 { $Result = 'Succeeded' }
        3 { $Result = 'SucceededWithErrors' }
        4 { $Result = 'Failed' }
        5 { $Result = 'Aborted' }
        default { $Result = $_ }
    }
    New-Object -TypeName PSObject -Property @{
        InstalledOn = Get-Date -Date $_.Date;
        Title       = $Title;
        KB = $KB;
        Status      = $Result
    }

} | Sort-Object -Descending:$true -Property InstalledOn