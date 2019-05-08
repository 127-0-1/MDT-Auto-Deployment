# Download URLs and versions for MDT & ADK
$MDTUrl = "https://download.microsoft.com/download/3/3/9/339BE62D-B4B8-4956-B58D-73C4685FC492/MicrosoftDeploymentToolkit_x64.msi"
$MDTVersion = "8456"
$ADKUrl = "http://download.microsoft.com/download/0/1/C/01CC78AA-B53B-4884-B7EA-74F2878AA79F/adk/adksetup.exe"
$ADKWinPEUrl = "http://download.microsoft.com/download/D/7/E/D7E22261-D0B3-4ED6-8151-5E002C7F823D/adkwinpeaddons/adkwinpesetup.exe"
$ADKVersion = "1809"
$OfficeDeploymentToolUrl = "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_11617-33601.exe"

# Disable x86 Support - If you are only using 64 bit OS, set this to $True. If not, set to $False
# If x86 is disabled, MDT is faster at re-generating boot images
$DisableX86Support = $True

# Change according to requirements, remove if not required (customsettings.ini)
# CustomSettings.ini options can be found here: https://docs.microsoft.com/en-us/sccm/mdt/toolkit-reference#properties-60
$CustomSettingsIni = @"
[Settings]
Priority=Default
Properties=MyCustomProperty

[Default]
TimeZoneName=GMT Standard Time
KeyboardLocale=0809:00000809
UserLocale=en-GB
UILanguage=en-GB
SkipCapture=NO
SkipBDDWelcome=YES
SkipApplications=NO
SkipAdminPassword=NO
SkipProductKey=NO
SkipProductKey=NO
SkipComputerBackup=NO
SkipBitLocker=NO
SkipTimeZone=NO
SkipDomainMembership=NO
SkipLocaleSelection=NO
SkipSummary=NO
"@

$Office365ConfigurationXml = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Monthly">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Groove" />
    </Product>
  </Add>
</Configuration>
"@