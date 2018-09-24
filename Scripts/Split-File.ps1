param(
    [parameter (Mandatory=$true)][string]$Path,
    [int]$MaxOutputSize = 50MB,
    [string]$OutputFolder,
    [string]$OutputPrefix,
    [string]$OutputExtension
)

if (! $(test-path $path)){
    write-error "File $path not found"
    exit
}

if(! $(test-path $OutputFolder)) {mkdir $OutputFolder}
$File = get-item $path
$ChunkCount = [math]::Ceiling($File.Length / $MaxOutputSize)
$ResultDigitsCount = [math]::Ceiling([math]::Log10($ChunkCount+1))


if (!$PSBoundParameters.ContainsKey('OutputPrefix')){
    $OutputPrefix = [io.path]::GetFileNameWithoutExtension($path)
}

if (!$PSBoundParameters.ContainsKey('OutputExtension')){
    $OutputExtension = [io.path]::GetExtension($path)
}

try{
    $reader = [io.file]::OpenText($Path)
    $filecount = 1
    try{
        $OutputFileName = "{0}_{1}{2}" -f ($OutputPrefix, $filecount.ToString("0"*$ResultDigitsCount), $OutputExtension)
        $OutputPath = Join-Path $OutputFolder $OutputFileName
        $writer = [io.file]::CreateText($OutputPath)
        $resultSize = 0
        while($reader.EndOfStream -ne $true) {
            $Line = $reader.ReadLine()
            if ($resultSize+$Line.Length -gt $MaxOutputSize) {
                $resultSize = 0
                $writer.Dispose();
                $filecount++
                $OutputFileName = "{0}_{1}{2}" -f ($OutputPrefix, $filecount.ToString("0"*$ResultDigitsCount), $OutputExtension)
                $OutputPath = Join-Path $OutputFolder $OutputFileName
                $writer = [io.file]::CreateText($OutputPath)
            }
            $writer.WriteLine($Line)
            $resultSize = $resultSize + $Line.Length
        }
    } finally {
        $writer.Dispose();
    }
}
finally{
    $reader.Dispose();
}