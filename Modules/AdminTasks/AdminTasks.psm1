Function Connect-ExchangeOnlineAT {
    <#
    .SYNOPSIS
    Establish connection to exchange online
    
    .DESCRIPTION
    Establish connection to exchange online and downloads powershell cmdlets

    .PARAMETER Credential
    PSCredential to be used during connection
    
    .EXAMPLE
    PS> Connect-ExchangeOnline
    
    Will ask for credential and use it to connect to Exchange online services

    #>
    [CmdletBinding()]
    param(
        [pscredential]$Credential = $(get-credential),
        [switch]$UseRPSProxyMethod

    )
    
    $ConnectionUri = 'https://outlook.office365.com/powershell-liveid/'
    if ($UseRPSProxyMethod) {$ConnectionUri = $ConnectionUri + "?proxymethod=rps"}
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $ConnectionUri -Credential $Credential -Authentication Basic -AllowRedirection
    Import-Module (Import-PSSession $Session -AllowClobber) -Global
}


Function Set-ScriptDigitalSignature{
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
    [CmdletBinding()]
    Param
        (
        [parameter(Mandatory=$true)][string]$FilePath,
        [parameter()][String]$CertThumbprint,
        [parameter()][string]$TimestampServer = 'http://timestamp.comodoca.com/rfc3161'
        )
    
    
    $crtlist = Get-ChildItem cert:\CurrentUser\My -CodeSigningCert
    If ($CertThumbPrint -ne "")
        {
        $crtlist = @($crtlist | Where-Object{$_.Thumbprint -eq $CertThumbprint})
        }
    switch($crtlist.length)
        {
        0 		{throw "No suitable certificate found"}	
        1 		{$cert = $crtlist[0]}
        Default	{$cert = $crtlist | Out-GridView -OutputMode Single -Title "Choose certificate"}
        }
    Set-AuthenticodeSignature -Certificate $cert -FilePath $FilePath -TimestampServer $TimestampServer
}

Function Get-SSLWebCertificate{
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
        [parameter (mandatory=$true)][string[]]$DnsName,
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
        Template=$Template
        Url = $url
        CertStoreLocation = $CertStoreLocation
        DnsName = $DnsName
    }
    if ($PSBoundParameters.ContainsKey('SubjectName')){
        $Splat['SubjectName']=$SubjectName
    } else {
        $Splat['SubjectName']="CN=$(@($DnsName)[0])"
    }
    if ($PSBoundParameters.ContainsKey('Credential')){
        $Splat['Credential']=$Credential
    }
    $Result = Get-Certificate @Splat
    if ($Result.Status -eq 'Issued'){
        if ($PSBoundParameters.ContainsKey('ExportToPfxPath')){
            if (Test-Path $ExportToPfxPath -isValid){
                if($(Test-Path $ExportToPfxPath) -and $(-not $Force)){
                    throw "File '$ExportToPfxPath' already exists"
                }
                $ExportFolder = Split-Path $ExportToPfxPath -Parent
                if (-not $(Test-Path -Path $ExportFolder)){
                        mkdir -Path $ExportFolder
                    }
                if(-not $PSBoundParameters.ContainsKey('Password')){
                    $Password = Read-Host "Password" -AsSecureString
                    }
                $CertPath = Join-Path $CertStoreLocation $Result.Certificate.Thumbprint
                $ExportFile = Export-PfxCertificate -Cert $CertPath -FilePath $ExportToPfxPath -Password $Password
                if ($ExportFile -and $RemoveAfterExport){
                    Remove-Item $CertPath
                    }
            } else {
                throw "Invalid path '$ExportToPfxPath'"
            }
        }
            
    }
}

