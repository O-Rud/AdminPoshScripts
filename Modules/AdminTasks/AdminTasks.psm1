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
    .PARAMETER ShowCertSelectionDialog
        Specify this switch parameter to show certificate selaction dialog. THis parameter is ignored if there are less than 2 codesign certificates present in the system
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
    <#
    .SYNOPSIS
        Creates IntuneWin App package from the files in the Target folder. Target folder is expected to have proper structure which can be created by the New-IntuneAppPkgFolder function.
    .DESCRIPTION
        Function takes files located in the source subfolder of the Target folder and copies them to the release folder. If release folder does not exist it will be created.
        Files and folders mentioned in ExcludeFiles and ExcludeFolders parameters respectively are not copied. Existing content of release folder will be overwritten.
        Then script Files in release folder are digitally signed using the best available codesign certificate in the user certificate store.
        Files from release folder are packaged using IntuneWinAppUtil.exe tool. Path to the tool either provided in the intuneWinPath parameter.
        If intuneWinPath parameter is not specified function will try to get location of IntuneWinAppUtil.exe from windows registry.
        Resulting intunewin file is stored in the output folder. If it does not exist it will be created automatically. Existing content of output folder will be overwritten

    .PARAMETER PackagePath
        Path to the folder containing app to package. This folder is expected to have the following structure:
        <PackageName>\
            source\
                install\
                    <app files>
                install.cmd
                install.ps1
                uninstall.cmd
                uninstall.ps1
            release\    (Optional)
            output\     (Optional)
        
        This structure can be automatically created using the New-IntuneAppPkgFolder function
    .PARAMETER intuneWinPath
        Path to the IntuneWinAppUtil.exe file. If not specified function will try to get it's location in the SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\IntuneWinAppUtil.exe registry key.
        This registry key us being automatically created if intuneWinPath is specified
    .PARAMETER RewriteIntuneWinAppPath
        Specify this parameter to update the path to the IntuneWinAppUtil.exe in the registry
    .PARAMETER ExcludeFiles
        List of files in the source folder which should bot be included in the resultin package. It can be either a file name, full file path or path relative to the package root folder
    .PARAMETER ExcludeFolders
        List of folders in the source folder which should bot be included in the resultin package. It can be either a foder name, full path or path relative to the package root folder
    .EXAMPLE
        New-IntuneWinPackage
        This command will create intunewin file from the data in the source subfolder of the current folder 
        Resulting package will be stored in the output folder created in the current location
        Location of IntuneWinAppUtil.exe will be taken from the registry if possible
    .EXAMPLE
        New-IntuneWinPackage -PackagePath C:\intuneapps\testapp -intuneWinPath C:\prg\IntuneWinAppUtil\IntuneWinAppUtil.exe -ExcludeFiles .\source\install\testignore.txt 
        This command will create C:\intuneapps\testapp\output\testapp.intuneWin file
        From the data in the C:\intuneapps\testapp\source folder
        Using the C:\prg\IntuneWinAppUtil\IntuneWinAppUtil.exe utility
        if there is no IntuneWinAppUtil.exe location stored in the registry it will be saved
    .EXAMPLE
        New-IntuneWinPackage -intuneWinPath C:\prg\IntuneWinAppUtil\IntuneWinAppUtil.exe -RewriteIntuneWinAppPath
        This command will create intunewin file from the data in the source subfolder of the current folder 
        Resulting package will be stored in the output folder created in the current location
        Using the C:\prg\IntuneWinAppUtil\IntuneWinAppUtil.exe utility
        Path in the registry will be updated regardless of it's previous existence in the registry

    #>
    param(
        [string]$PackagePath, #Path to the folder containing app to package    
        [string]$intuneWinPath, #Path to the IntuneWin.exe file 
        [switch]$RewriteIntuneWinAppPath, #Force Update IntuneWin app path in the registry
        [string[]]$ExcludeFiles = @(), #Files not to be included in release
        [string[]]$ExcludeFolders = @() #Files not to be included in release
    )
    
    $IntuneWinRegPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\IntuneWinAppUtil.exe"
    foreach ($hive in @("HKCU", "HKLM")) {
        $Regpath = "$($hive):\$IntuneWinRegPath"
        if (Test-Path $Regpath) {
            $intuneWinAppPath = Get-ItemPropertyValue -Path $Regpath -Name '(default)'
            if ($intuneWinAppPath) { break }
        }
    }
    
    if ($PSBoundParameters.ContainsKey('intuneWinPath')) {
        if (Test-Path $intuneWinPath) {
            if (-not $(Test-Path [string]$intuneWinAppPath) -or $RewriteIntuneWinAppPath) {
                New-Item -Path "HKCU:\$IntuneWinRegPath" -Value $intuneWinPath -Force
                Set-ItemProperty -Path "HKCU:\$IntuneWinRegPath" -Name "Path" -Value $(Split-Path $intuneWinPath -Parent)
            }
        }
        else {
            throw "File $intuneWinPath not found"
        }
    }
    else {
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
    
    $Arglist = $SourcePath, $ReleasePath, "/MIR", "/XO"
    if ($ExcludeFiles.count -gt 0) {
        $Arglist += "/XF"
        foreach ($item in $ExcludeFiles) {
            if ($item -match "^\.\\") {
                $Arglist += $($item -replace "^\.", $PackagePath)
            }
            else {
                $Arglist += $item
            }
        }
    }
    if ($ExcludeFolders.count -gt 0) {
        $Arglist += "/XD"
        foreach ($item in $ExcludeFolders) {
            if ($item -match "^\.\\") {
                $Arglist += $($item -replace "^\.", $PackagePath)
            }
            else {
                $Arglist += $item
            }
        }
    }
    $null = Start-Process "robocopy.exe" -ArgumentList $arglist -NoNewWindow -PassThru -Wait

    $projectname = (Get-item $sourcePath ).parent.name

    Get-ChildItem -Path $ReleasePath -Include *.ps1, *.psm1 -Recurse | ForEach-Object {
        $Signature = Get-AuthenticodeSignature $($_.fullname)
        if ($Signature.Status -ne "Valid") {
            Set-CodeDigitalSignature -FilePath $($_.fullname)
        }
    }

    $intuneArgs = "-c", "`"$ReleasePath`"", "-s", "`"$ReleasePath\install.cmd`"", "-o", "`"$OutputPath`"", "-q"
    $null = Start-Process $intuneWinPath -ArgumentList $intuneArgs -NoNewWindow -PassThru -Wait
    if (Test-Path "$OutputPath\$projectname.intuneWin") { Remove-Item "$OutputPath\$projectname.intuneWin" }
    Rename-Item "$OutputPath\install.intunewin" -NewName "$projectname.intuneWin" -Force
}

Function New-IntuneAppPkgTemplate{
    <#
    .SYNOPSIS
        Creates a folder structure for new intune app package which is suitable for packaging by New-IntuneWinPackage Function
    .DESCRIPTION
        Creates the following structure in the Target directory specified in the Path parameter.
    
        <AppName>\
            source\
                install\
                    ...
                install.cmd
                install.ps1
                uninstall.cmd
                uninstall.ps1

    .PARAMETER AppName
        Name of the app to be published.
    .PARAMETER Path
        Path to the folder where the new folder structure should be created. Not including the app name.
        If Path is not specified the default value is current folder.
    .EXAMPLE
        New-IntuneAppPkgFolder TestApp1
        This command will create a new folder called TestApp1 in the current location with the necesary subfolders and files for packaging with New-IntuneWinPackage
    .EXAMPLE
        New-IntuneAppPkgFolder -AppName TestApp1 -Path C:\Temp
        This command will create a new folder C:\Temp\TestApp1 with the necesary subfolders and files for packaging with New-IntuneWinPackage
    #>
    param(
        [parameter(Mandatory)][string]$AppName,
        [string]$Path
    )
    if (-not ($PSBoundParameters.ContainsKey('Path'))){
        $Path = (Get-Item -Path ".\").fullname
    }
    $NewAppPkgPath = Join-Path $Path $AppName
    if (Test-Path $NewAppPkgPath) {
        throw "Folder $NewAppPkgPath already exists"
    }
    mkdir $NewAppPkgPath
    mkdir "$NewAppPkgPath\source"
    mkdir "$NewAppPkgPath\source\install"
    $InstallCmd = @"
@ECHO OFF
IF EXIST "%WINDIR%\SysNative\WindowsPowershell\v1.0\PowerShell.exe" (
    "%WINDIR%\SysNative\WindowsPowershell\v1.0\PowerShell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0%install.ps1"
) ELSE (
    "%WINDIR%\System32\WindowsPowershell\v1.0\PowerShell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0%install.ps1"
)
"@
    $UninstallCmd =@"
@ECHO OFF
IF EXIST "%WINDIR%\SysNative\WindowsPowershell\v1.0\PowerShell.exe" (
    "%WINDIR%\SysNative\WindowsPowershell\v1.0\PowerShell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
) ELSE (
    "%WINDIR%\System32\WindowsPowershell\v1.0\PowerShell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
)
"@
    Set-Content -Path "$NewAppPkgPath\source\install.cmd" -Value $InstallCmd
    Set-Content -Path "$NewAppPkgPath\source\uninstall.cmd" -Value $UninstallCmd
    New-Item -Path "$NewAppPkgPath\source\install.ps1"
    New-Item -Path "$NewAppPkgPath\source\uninstall.ps1"
}

Set-Alias -Name SignCode -Value 'Set-CodeDigitalSignature' -Option ReadOnly -Description "Digitally signs an executable file like Powershell script or *.exe" -Force

Export-ModuleMember -Function * -Alias *