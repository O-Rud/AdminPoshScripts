<#
.SYNOPSIS
	Script resizes every image in spesified folder to desired size on longest dimension preserving aspect ratio
.PARAMETER InPath
	Path to the folder, containing images to resize
.PARAMETER MaxSize
	Reslting image length on it's longest dimension
#>
param
(
    [string]$InPath = $(throw "Enter path to folder containing files"),
    [int]$MaxSize = $(throw "Enter te length of longest dimension of resulting image")
)

Function Get-ImageEncoder ([System.Drawing.Imaging.Imageformat]$format) {
    [System.Drawing.Imaging.ImageCodecInfo]::GetImageDecoders() | Where-Object {$_.formatid -eq $format.guid}
}

Function Resize-Image {
    param(
        [string]$InputImagePath,
        [string]$OutputImagePath,
        [int]$maxsize = 128,
        [switch]$ResizeOnlyBigger
    )
    Write-Verbose "Resizing $InputImagePath"
    add-type -AssemblyName system.drawing
    $fullimg = $null
    try {
        $Fstream = New-Object system.IO.FileStream ($InputImagePath, [io.FileMode]::Open, [io.FileAccess]::Read)
        $fullimg = [System.Drawing.Image]::FromStream($Fstream)
    }
    catch {
        if ($Fstream) {$Fstream.dispose()}
        if ($fullimg) {$fullimg.dispose()}
        throw "$InputImagePath is not valid image file"
    }
    if ($fullimg.width -gt $fullimg.height) {
        [double]$ratio = $maxsize / $fullimg.width
    }
    else {
        [double]$ratio = $maxsize / $fullimg.height
    }
    if ((-not $ResizeOnlyBigger) -or ($ratio -lt 1)) {
        [int]$newwidth = $fullimg.width * $ratio
        [int]$newheight = $fullimg.height * $ratio
        $newImg = New-Object System.Drawing.Bitmap($newwidth, $newheight)
        $gr = [System.Drawing.Graphics]::FromImage($newImg)
        $gr.InterpolationMode = [System.Drawing.drawing2d.InterpolationMode]::HighQualityBicubic
        $gr.SmoothingMode = [System.Drawing.drawing2d.SmoothingMode]::HighQuality
        $gr.PixelOffsetMode = [System.Drawing.drawing2d.PixelOffsetMode]::HighQuality
        $gr.CompositingQuality = [System.Drawing.drawing2d.CompositingQuality]::HighQuality
        $gr.DrawImage($fullImg, 0, 0, $newwidth, $newheight)
        $gr.Dispose()
        $fullimg.Dispose()
        $Fstream.close()
        $Fstream.dispose()
        $myEncoderParams = New-Object System.Drawing.Imaging.EncoderParameters (1)
        $myEncoderParams.Param[0] = new-object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 65)
        $newImg.save($OutputImagePath, $(Get-ImageEncoder jpeg), $myEncoderParams)
        $newImg.dispose()
    }
    else {
        $fullimg.dispose()
        $Fstream.dispose()
    }
}

Get-ChildItem $InPath -recurse -Include *.jpg | ForEach-Object {
    try	{
        Resize-Image -InputImagePath $_.fullname -OutputImagePath $_.fullname -maxsize $maxsize -ResizeOnlyBigger -showlog $ShowLog
    }
    catch {
        $_
    }
}