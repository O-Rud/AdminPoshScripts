function Get-ProcessOutput {
    Param (
        [Parameter(Mandatory = $true)]$FilePath,
        $ArgumentList,
        [switch]$Wait,
        [int]$TimeOutMilliSeconds = -1
    )
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.FileName = $FilePath
    if ($ArgumentList) { $process.StartInfo.Arguments = $ArgumentList }
    $process.Start() | out-null
    if ($Wait) {
        if (-not $process.WaitForExit($TimeOutMilliSeconds)) {
            $process.Kill()
        }
    
    }
    $StandardOutput = $process.StandardOutput.ReadToEnd()
    $StandardError = $process.StandardError.ReadToEnd()
    $output = [PSCustomObject]@{
        StandardOutput = $StandardOutput
        StandardError  = $StandardError
        ExitCode       = $process.ExitCode
    }
    $process.Close()
    return $output
}