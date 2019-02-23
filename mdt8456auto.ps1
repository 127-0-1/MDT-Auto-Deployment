# Microsoft Deployment Toolkit 8456 Automatic Setup
# Author: Sam Tucker (https://github.com/pwshMgr)
# Version: 3.3.2
# Release date: 27/01/2019
# Tested on Windows 10 1607, Windows Server 2016 & 2019

#Requires -RunAsAdministrator

#Input Parameters
param (
    [Parameter(Mandatory = $true)]
    [string] $SvcAccountPassword,

    [Parameter(Mandatory = $true)]
    [ValidateScript( {Test-Path $_})]
    [string]$DSDrive,

    [Parameter(Mandatory = $false)]
    [switch] $IncludeApplications,

    [Parameter(Mandatory = $false)]
    [switch] $InstallWDS
)

$ErrorActionPreference = "Stop"
$DSDrive = $DSDrive.TrimEnd("\")

#Import Configuration JSON
$Configuration = Test-Path "$PSScriptRoot\configuration.ps1"
if (!$Configuration) {
    Write-Error "configuration.ps1 not found"
}

Try {
    . "$PSScriptRoot\configuration.ps1"
} Catch {
    Write-Error "Check configuration.ps1 for syntax errors"
}

write "Downloading MDT $MDTVersion"
$params = @{
    Source      = $MDTUrl
    Destination = "$PSScriptRoot\MicrosoftDeploymentToolkit_x64.msi"
}
Start-BitsTransfer @params

write "Downloading ADK $ADKVersion"
$params = @{
    Source      = $ADKUrl
    Destination = "$PSScriptRoot\adksetup.exe"
}
Start-BitsTransfer @params

write "Downloading ADK $ADKVersion WinPE Addon"
$params = @{
    Source      = $ADKWinPEUrl
    Destination = "$PSScriptRoot\adkwinpesetup.exe"
}
Start-BitsTransfer @params

write "Installing MDT $MDTVersion"
$params = @{
    Wait         = $True
    FilePath     = "msiexec"
    ArgumentList = "/i ""$PSScriptRoot\MicrosoftDeploymentToolkit_x64.msi"" /qn"
}
start @params

write "Installing ADK $ADKVersion"
$params = @{
    Wait         = $True
    FilePath     = "$PSScriptRoot\adksetup.exe"
    ArgumentList = "/quiet /features OptionId.DeploymentTools"
}
start @params

write "Installing ADK $ADKVersion WinPE Addon"
$params = @{
    Wait         = $True
    FilePath     = "$PSScriptRoot\adkwinpesetup.exe"
    ArgumentList = "/quiet /features OptionId.WindowsPreinstallationEnvironment"
}
start @params

write "Importing MDT Module"
$ModulePath = "$env:ProgramFiles\Microsoft Deployment Toolkit"+
              "\bin\MicrosoftDeploymentToolkit.psd1"
Import-Module $ModulePath

write "Creating local Service Account for DeploymentShare"
$params = @{
    Name                 = "svc_mdt"      
    Password             = (ConvertTo-SecureString $SvcAccountPassword -AsPlainText -Force)
    AccountNeverExpires  = $true
    PasswordNeverExpires = $true
}
New-LocalUser @params

write "Creating Deployment Share Directory"
New-Item -Path "$DSDrive\DeploymentShare" -ItemType Directory

$params = @{
    Name       = "DeploymentShare$"
    Path       = "$DSDrive\DeploymentShare"
    ReadAccess = "$env:COMPUTERNAME\svc_mdt"
}
New-SmbShare @params

$params = @{
    Name        = "DS001"
    PSProvider  = "MDTProvider"
    Root        = "$DSDrive\DeploymentShare"
    Description = "MDT Deployment Share"
    NetworkPath = "\\$env:COMPUTERNAME\DeploymentShare$"
}
New-PSDrive @params -Verbose | Add-MDTPersistentDrive -Verbose

write "Checking for wim files to import"
$Wims = Get-ChildItem $PSScriptRoot -Filter "*.wim" | Select -ExpandProperty FullName
if (!$Wims) {
    write "No wim files found"
}

if ($Wims) {
    foreach($Wim in $Wims){
    $WimName = (Split-Path $Wim -Leaf).TrimEnd(".wim")
    write "$WimName found - will import"
    $params = @{
        Path              = "DS001:\Operating Systems"
        SourceFile        = $Wim
        DestinationFolder = $WimName
    }
    $OSData = Import-MDTOperatingSystem @params -Verbose
    }
}

#Create Task Sequence for each Operating System
write "Creating Task Sequence for each imported Operating System"
$OperatingSystems = Get-ChildItem -Path "DS001:\Operating Systems"

if ($OperatingSystems) {
    [int]$counter = 0
    foreach ($OS in $OperatingSystems){
    $Counter++
    $WimName = Split-Path -Path $OS.Source -Leaf
    $params = @{
        Path                = "DS001:\Task Sequences"
        Name                = "$($OS.Description) in $WimName"
        Template            = "Client.xml"
        Comments            = ""
        ID                  = $Counter
        Version             = "1.0"
        OperatingSystemPath = "DS001:\Operating Systems\$($OS.Name)"
        FullName            = "fullname"
        OrgName             = "org"
        HomePage            = "about:blank"
        Verbose             = $true
    }
    Import-MDTTaskSequence @params
    }
}

if (!$wimPath) {
    write "Skipping as no WIM found"
}

#Edit Bootstrap.ini
$BootstrapIni = @"
[Settings]
Priority=Default
[Default]
DeployRoot=\\$env:COMPUTERNAME\DeploymentShare$
SkipBDDWelcome=YES
UserDomain=$env:COMPUTERNAME
UserID=svc_mdt
UserPassword=$SvcAccountPassword
"@

$params = @{
    Path  = "$DSDrive\DeploymentShare\Control\Bootstrap.ini"
    Value = $BootstrapIni
    Force = $True
}
sc @params -Confirm:$False

write "Disabling x86 Support"
$DeploymentShareSettings = "$DSDrive\DeploymentShare\Control\Settings.xml"
$xmlDoc = [XML](Get-Content $DeploymentShareSettings)
$xmldoc.Settings.SupportX86 = "False"
$xmlDoc.Save($DeploymentShareSettings)

#Create LiteTouch Boot WIM & ISO
write "Creating LiteTouch Boot Media"
Update-MDTDeploymentShare -Path "DS001:" -Force -Verbose

#Download & Import Office 365 2016
if ($IncludeApplications) {
    write "Downloading Office Deployment Toolkit"
    New-Item -ItemType Directory -Path "$PSScriptRoot\odt"
    $params = @{
        Source      = "https://download.microsoft.com/download"+
        "/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_11306-33602.exe"
        Destination = "$PSScriptRoot\odt\officedeploymenttool.exe"
    }
    Start-BitsTransfer @params

    write "Extracting Office Deployment Toolkit"
    $params = @{
        FilePath     = "$PSScriptRoot\odt\officedeploymenttool.exe"
        ArgumentList = "/quiet /extract:$PSScriptRoot\odt"
    }
    start @params -Wait
    Remove-Item "$PSScriptRoot\odt\officedeploymenttool.exe" -Force -Confirm:$false
    write "Remove Visio"
    $xml = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Monthly">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Groove" />
    </Product>
  </Add>
</Configuration>
"@
    sc -Path "$PSScriptRoot\odt\configuration.xml" -Value $xml -Force -Confirm:$false

    write "Importing Office 365 into MDT"
    $params = @{
        Path                  = "DS001:\Applications"
        Name                  = "Microsoft Office 365 2016 Monthly"
        ShortName             = "Office 365 2016"
        Publisher             = "Microsoft"
        Language              = ""
        Enable                = "True"
        Version               = "Monthly"
        Verbose               = $true
        CommandLine           = "setup.exe /configure configuration.xml"
        WorkingDirectory      = ".\Applications\Microsoft Office 365 2016 Monthly"
        ApplicationSourcePath = "$PSScriptRoot\odt" 
        DestinationFolder     = "Microsoft Office 365 2016 Monthly"
    }
    Import-MDTApplication @params
}

if ($IncludeApplications) {
    $Applist = gc "$PSScriptRoot\applications.json" | ConvertFrom-Json
    foreach ($Application in $AppList) {
        New-Item -Path "$PSScriptRoot\mdt_apps\$($application.name)" -ItemType Directory -Force
        $params = @{
            Source      = $Application.download
            Destination = "$PSScriptRoot\mdt_apps\$($application.name)\$($Application.filename)"
        }
        Start-BitsTransfer @params
        $params = @{
            Path                  = "DS001:\Applications"
            Name                  = $Application.name
            ShortName             = $Application.name
            Publisher             = ""
            Language              = ""
            Enable                = "True"
            Version               = $Application.version
            Verbose               = $true
            CommandLine           = $Application.install
            WorkingDirectory      = ".\Applications\$($Application.name)"
            ApplicationSourcePath = "$PSScriptRoot\mdt_apps\$($application.name)"
            DestinationFolder     = $Application.name
        }
        Import-MDTApplication @params
    }
    Remove-Item -Path "$PSScriptRoot\mdt_apps" -Recurse -Force -Confirm:$false
}

#Install WDS
If ($InstallWDS) {
    $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($OSInfo.ProductType -eq 1) {
        write "Workstation OS - WDS Not available"
    }
    else {
        write "Server OS - Checking if WDS available on this version"
        $WDSCheck = Get-WindowsFeature -Name WDS
        if ($WDSCheck) {
            write "WDS Role Available - Installing"
            Add-WindowsFeature -Name WDS -IncludeAllSubFeature -IncludeManagementTools
            $WDSInit   = wdsutil /initialize-server /remInst:"$DSDrive\remInstall" /standalone
            $WDSConfig = wdsutil /Set-Server /AnswerClients:All
            $params = @{
                Path         = "$DSDrive\DeploymentShare\Boot\LiteTouchPE_x64.wim"
                SkipVerify   = $True
                NewImageName = "MDT Litetouch"
                
            }
            Import-WdsBootImage @params
        }
        else {
            write "WDS Role not available on this version of Server"
        }
    }
}

#Finish
write "Script Finished"
Pause