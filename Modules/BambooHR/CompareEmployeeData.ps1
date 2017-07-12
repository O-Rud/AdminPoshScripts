Import-Module BambooHR
Import-Module CertEncrypt

$EncryptedApiKey = 'i6t3SNzcVq5GcMdvCsECFQWV8TOARBjySh8tbmj/3e/qxKKlUnkWYWxJaZPdRCjAWNCCCwO/EE3X2GdPPwt55UaMlucgdnEAbq/UEjkPvylZEtRLuqKwUcOMlYta/w2zqLxTPzXQLDu0qnFNftq1jZ7NWdJadTLwz8T6PHp7vfWyt3wkIOD2TQ1eFvHHYT8HRYX/R4PNjnIfdXR9KB4bH9c+76G8mTvzq2I9xFA+IfMEvdg454hNGMFRNxstQefF/owzlsiMZno3XYQOGOoZvgEuWcpUWryQ+r9XSkdpWLnA/ckEOgIND7w6BBqmSdc3z+D2K2+m6l4JaaqyPcsbaA=='
$ApiKey = Get-CertDecryptedString -SourceString $EncryptedApiKey -CertThumbprint 2644DEF38137A8037BE0C1F4B2FF0599607CCECA
$Subdomain = "depositsolutions"
$PSDefaultParameterValues."*-Bamboo*:ApiKey" = $ApiKey
$PSDefaultParameterValues."*-Bamboo*:Subdomain" = $Subdomain

$fieldMatch = @{
    91                                                           = 'Line Manager'
    address1                                                     = 'Number'
    address2                                                     = 'Street'
    city                                                         = 'City'
    customAkademischerGrad                                       = 'Akademischer Grad'
    customBIC                                                    = 'BIC'
    customCitizenship                                            = 'Citizenship'
    4355                            = 'Contract Class'
    customCountryofBirth                                         = 'Country of Birth'
    customHealthInsurance                                        = 'Health Insurance (Staturory) (code)'
    4360 = 'Highest Education'
    4359        = 'Highest school education'
    customIBAN                                                   = 'IBAN'
    'customInternshipClassification/Praktikumsart'               = 'Internship Classification'
    customPersonegruppe                                          = 'Personengruppe(Social Insurance Group)'
    customPlaceofBirth                                           = 'Place of Birth'
    'customPrimary/SecondaryEmployment'                          = 'Primary-/Secondary Employment'
    customReligiousGroup                                         = 'Religous Group'
    customSocialInsuranceNumber                                  = 'Social Insurance Number'
    customTaxAllowanceforDependentChildren                       = 'Children Tax Benefit'
    customTaxClass                                               = 'Tax Class'
    customTaxID                                                  = 'Tax ID'
    customWorkPermitValidUntil                                   = 'Work Permit'
    dateOfBirth                                                  = 'Birthday'
    department                                                   = 'Department'
    Division                                                     = 'Team'
    employeeNumber                                               = 'Pers.Nr.'
    firstName                                                    = 'First Name'
    gender                                                       = 'Gender'
    hireDate                                                     = 'Entry'
    jobTitle                                                     = 'Position Title'
    lastName                                                     = 'Name'
    location                                                     = 'Org'
    maritalStatus                                                = 'Merital Status'
    terminationDate                                              = 'Exit'
    zipcode                                                      = 'Code'

}

$PersDataFilePath = 'C:\Work\Bamboo\Copy of 170711_Bamboo_Import_Oleksii.csv'
$DataList = Import-Csv $PersDataFilePath -Delimiter ';' -Encoding UTF8
$DataHashTable = @{}
foreach ($Item in $DataList) {
    $DataHashTable[$Item.'Pers.Nr.'] = $Item
}

$id = 1
$FieldsMetadata = Invoke-BambooAPI -ApiCall "meta/fields/" -ApiKey $ApiKey -Subdomain $Subdomain
$FieldTypes = @{}
foreach ($item in $FieldsMetadata){
    $FieldTypes[$Item.id] = $Item.type
    $FieldTypes[$Item.alias] = $Item.type
}
$Fieldlist = $fieldMatch.Keys
$Employee = Get-BambooEmployee -id $id -Properties $($Fieldlist)
$EmployeeNumber = $Employee.employeeNumber
$Result = foreach ($Field in $Fieldlist){
    $BambooValue = ([string]$($Employee.$Field)).trim()
    $ListName = $fieldMatch[$Field]
    $ListValue = ([string]$($DataHashTable[$EmployeeNumber].$ListName)).Trim()
    [pscustomobject]@{
        EmployeeNumber = $EmployeeNumber
        BambooName = $Field
        BambooValue = $BambooValue
        ListName = $ListName
        ListValue = $ListValue
        Match = $BambooValue -eq $ListValue
    }
}
$Result | ?{$_.match -eq $false}