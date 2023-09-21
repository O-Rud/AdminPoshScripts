Function Set-CodeDigitalSignature {
    <#
    .Synopsis
        Adds digital signature to powershell script or other file
    .Parameter FilePath
        Specifies the path to a file that is being signed.
    .Parameter CertThumbprint
        Optional Parameter. Specifies thumbprint of certificate to be used for signature.
        If not specified then possible two ways:
            1) Only single certificate available in user profile - it will be used automatically
            2) Multiple certificates available - user will be prompted to choose certificate
    .Parameter TimestampServer
        Optional Parameter. Refers to Timestamp Server which will be used for digital signature. Default value is http://timestamp.comodoca.com/rfc3161
    #>
    [CmdletBinding(DefaultParameterSetName = 'CertThumbprint')]
    Param
    (
        [parameter(Mandatory = $true, Position = 0)][string]$FilePath,
        [parameter(ParameterSetName = "CertThumbprint")][String]$CertThumbprint,
        [parameter(ParameterSetName = "CertSelectionDialog")][switch]$ShowCertSelectionDialog,
        [parameter()][string]$TimestampServer = 'http://timestamp.comodoca.com?td=sha256'
    )
    
    If ($PSBoundParameters.ContainsKey('CertThumbprint')) {
        $cert = Get-Item "Cert:\CurrentUser\My\$CertThumbPrint"
    }

    If ($PSBoundParameters.ContainsKey('ShowCertSelectionDialog')) {
        $crtlist = Get-ChildItem cert:\CurrentUser\My -CodeSigningCert
        switch ($crtlist.length) {
            0 { throw "No suitable certificate found" }	
            1 { $cert = $crtlist[0] }
            Default	{ $cert = $crtlist | Out-GridView -OutputMode Single -Title "Choose certificate" }
        }
    }

    if ($null -eq $cert) {
        $d = get-date
        $cert = Get-ChildItem cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.NotBefore -lt $d -and $_.notafter -gt $d } | Sort-Object -Property 'NotAfter' -Descending | Select-Object -First 1
    }

    if ($cert) {
        Set-AuthenticodeSignature -Certificate $cert -FilePath $FilePath -TimestampServer $TimestampServer -HashAlgorithm SHA256
    }
    else {
        throw "No CodeSign certificate was found"
    }
    
}

Function Get-SSLWebCertificate {
    <#
    .SYNOPSIS
        Requests SSL Certificate from custom template. If necessary exports it to pfx and removes from certificate store.
    .DESCRIPTION
        It's a wrap-up function for Get-Certificate cmdlet with some default values and additional features like export new certificate to a file.
    .PARAMETER SubjectName
        Specifies Subjectname for certificate. If not set, first name in DNS name list wil be used instead
    .PARAMETER DnsName
        Specifies list of DNS names. They will appear in certificate's subject aternative names list
    .PARAMETER Template
        Certificate template name. Default value is SSLWebServer
    .PARAMETER Url
        CA url to be used for certificate request. Default value is 'ldap:', which corresponds to Active Directory deficed CA
    .PARAMETER CertStoreLocation
        Path to certificate store. Default value is cert:\LocalMachine\My\. In most cases with shouldn't be changed
    .PARAMETER Credential
        Credential to be used for certificae request. By default if CertStoreLocation was not changed Computer credentials will be used.
    .PARAMETER ExportToPfxPath
        Specifies where to export certificate pfx. If not set, certificate won't be exported
    .PARAMETER Password
        Encryption password for pfx. If not set, user input will be necessary.
    .PARAMETER RemoveAfterExport
        Use this parameter if you want to remove newly requested certificate after it has been exported
    .PARAMETER Force
        By defaut cmdlet won't overwrite existing pfx file by export. Use this parameter to overwrite file if necessary.
    .EXAMPLE
        Get-SSLWebCertificate -DnsName test.example.com
        
        Certificate with subject name CN=test.example.com and SAN DNS=test.example.com will be requested using default template SSLWebServer and stored in machine certificate store. No further actions will be performed.
    .EXAMPLE
        Get-SSLWebCertificate -DnsName test.example.com -ExportToPfxPath c:\temp\test.pfx -RemoveAfterExport
        
        Certificate with subject name CN=test.example.com and SAN DNS=test.example.com will be requested using default template SSLWebServer
        Machine certificate store will be used as temporary storage. Certificate will be exported to c:\temp\test.pfx. User will be prompted for password.
        After Export certificate will be removed from machine store
    .EXAMPLE
        Get-SSLWebCertificate -SubjectName CN=test -DnsName test.example.com -ExportToPfxPath c:\temp\test.pfx -RemoveAfterExport -Password $(Convert-tosecureString "Pa$$w0rd" -AsPlainText -Force)

        Certificate with subject name CN=test and SAN DNS=test.example.com will be requested using default template SSLWebServer
        Machine certificate store will be used as temporary storage. Certificate will be exported to c:\temp\test.pfx and protected with password "Pa$$w0rd"
        After Export certificate will be removed from machine store
    #>
    [CmdletBinding()]
    param(
        [string]$SubjectName,
        [parameter (mandatory = $true)][string[]]$DnsName,
        [string]$Template = 'SSLWebServer',
        [string]$url = 'ldap:',
        [string]$CertStoreLocation = "cert:\LocalMachine\My\",
        [PSCredential]$Credential,
        [string]$ExportToPfxPath,
        [securestring]$Password,
        [switch]$RemoveAfterExport,
        [switch]$Force
    )
    $Splat = @{
        Template          = $Template
        Url               = $url
        CertStoreLocation = $CertStoreLocation
        DnsName           = $DnsName
    }
    if ($PSBoundParameters.ContainsKey('SubjectName')) {
        $Splat['SubjectName'] = $SubjectName
    }
    else {
        $Splat['SubjectName'] = "CN=$(@($DnsName)[0])"
    }
    if ($PSBoundParameters.ContainsKey('Credential')) {
        $Splat['Credential'] = $Credential
    }
    $Result = Get-Certificate @Splat
    if ($Result.Status -eq 'Issued') {
        if ($PSBoundParameters.ContainsKey('ExportToPfxPath')) {
            if (Test-Path $ExportToPfxPath -isValid) {
                if ($(Test-Path $ExportToPfxPath) -and $(-not $Force)) {
                    throw "File '$ExportToPfxPath' already exists"
                }
                $ExportFolder = Split-Path $ExportToPfxPath -Parent
                if (-not $(Test-Path -Path $ExportFolder)) {
                    mkdir -Path $ExportFolder
                }
                if (-not $PSBoundParameters.ContainsKey('Password')) {
                    $Password = Read-Host "Password" -AsSecureString
                }
                $CertPath = Join-Path $CertStoreLocation $Result.Certificate.Thumbprint
                $ExportFile = Export-PfxCertificate -Cert $CertPath -FilePath $ExportToPfxPath -Password $Password
                if ($ExportFile -and $RemoveAfterExport) {
                    Remove-Item $CertPath
                }
            }
            else {
                throw "Invalid path '$ExportToPfxPath'"
            }
        }
            
    }
}

Function New-IntuneWinPackage {
    param(
        [string]$intuneWinPath, #Path to the IntuneWin.exe file 
        [string]$PackagePath, #Path to the folder containing app to package
        [switch]$RewriteIntuneWinAppPath,
        [string[]]$ExcludePaths = @()                       #Files not to be included in release
    )
    
    $IntuneWinRegPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\IntuneWinAppUtil.exe"
    foreach($hive in @("HKCU","HKLM")){
        $Regpath = "$($hive):\$IntuneWinRegPath"
        if (Test-Path $Regpath) {
            $intuneWinAppPath = Get-ItemPropertyValue -Path $Regpath -Name '(default)'
            if ($intuneWinAppPath) {break}
        }
    }
    
    if ($PSBoundParameters.ContainsKey('intuneWinPath')) {
        if (Test-Path $intuneWinPath){
            if (-not $(Test-Path [string]$intuneWinAppPath) -or $RewriteIntuneWinAppPath){
                New-Item -Path "HKCU:\$IntuneWinRegPath" -Value $intuneWinPath -Force
                Set-ItemProperty -Path "HKCU:\$IntuneWinRegPath" -Name "Path" -Value $(Split-Path $intuneWinPath -Parent)
            }
        } else {
            throw "File $intuneWinPath not found"
        }
    } else {
        $intuneWinPath = [string]$intuneWinAppPath
    }
    if (-not $(Test-path $intuneWinPath)) { throw "IntuneWin.exe was not found" }
    
    if (-not $PSBoundParameters.ContainsKey('PackagePath')) {
        $PackagePath = (get-item ".\").fullname
    }

    $SourcePath = Join-Path $PackagePath "source"
    $OutputPath = Join-Path $PackagePath "output"
    $ReleasePath = Join-Path $PackagePath "release"

    if (-not $(Test-Path $PackagePath)) {
        throw "Folder $PackagePath does not exist"
    }

    if (-not $(Test-Path $SourcePath)) {
        throw "Package Folder $PackagePath does not contain `"source`" folder"
    }

    if (0 -eq (Get-ChildItem -Path $SourcePath -Attributes !Directory -Recurse).count) {
        throw "Folder $SourcePath does not contain any files"
    }

    if (-not $(Test-Path $ReleasePath)) { mkdir $ReleasePath }
    foreach ($item in $(Get-ChildItem -path $SourcePath -Recurse)) {
        if ($ExcludePaths -notcontains $item.fullname) {
            if ($item.PSIsContainer) {
                Copy-Item -Path $item.fullname -Force -Destination $($item.parent.fullname.replace($SourcePath, $ReleasePath))
            }
            else {
                Copy-Item -Path $item.fullname -Force -Destination $($item.fullname.replace($SourcePath, $ReleasePath))
            }
        }
    }

    $projectname = (Get-item $sourcePath ).parent.name

    Get-ChildItem -Path $ReleasePath -Include *.ps1, *.psm1 -Recurse | ForEach-Object {
        $Signature = Get-AuthenticodeSignature $($_.fullname)
        if ($Signature.Status -ne "Valid") {
            Set-CodeDigitalSignature -FilePath $($_.fullname)
        }
    }

    $intuneArgs = "-c", $ReleasePath, "-s", "$ReleasePath\install.cmd", "-o", $OutputPath, "-q"
    $null = Start-Process $intuneWinPath -ArgumentList $intuneArgs -NoNewWindow -PassThru -Wait
    if (Test-Path "$OutputPath\$projectname.intuneWin") { Remove-Item "$OutputPath\$projectname.intuneWin" }
    Rename-Item "$OutputPath\install.intunewin" -NewName "$projectname.intuneWin" -Force
}