# Microsoft Deployment Toolkit Automatic Setup
# Author: Sam Tucker (https://github.com/pwshMgr)
# Version: 3.4.0
# Release date: 09/05/2019
# Tested on Windows 10 1607, Windows Server 2016 & 2019

#Requires -RunAsAdministrator

#Input Parameters
param (
    [Parameter(Mandatory = $true)]
    [string] $SvcAccountPassword,

    [Parameter(Mandatory = $true)]
    [ValidateScript( { Test-Path $_ })]
    [string]$DSDrive,

    [Parameter(Mandatory = $false)]
    [switch] $IncludeApplications,

    [Parameter(Mandatory = $false)]
    [switch] $InstallWDS
)

$DSDrive = $DSDrive.TrimEnd("\")

$Logfile = "$PSScriptRoot\mdt-auto-deployment.log"

function Write-Log {
    param (
        [Parameter(Mandatory = $True)]
        [string]$Log,
        [Parameter(Mandatory = $True)]
        [ValidateSet("Info", "Warn", "Error")]
        [string]$Level
    )
    $Date = Get-Date
    if ($Level -eq "Info") {
        Write-Host -ForegroundColor Green "$Date ($Level): $Log"
    } 
    elseif ($Level -eq "Warn") {
        Write-Host -ForegroundColor Yellow "$Date ($Level): $Log"
    } 
    else {
        Write-Host -ForegroundColor Red "$Date ($Level): $Log"
    }
    Add-content $Logfile -Value "$Date ($Level): $Log"
}

function Exit-Script {
    Pause
    Exit
}

function Download-File {
    param (
        [Parameter(Mandatory = $True)]
        [string]$Source,
        [Parameter(Mandatory = $True)]
        [string]$Destination
    )
    [bool]$StopLoop = $False
    [int]$RetryCount = "0"
    do {
        try {
            Start-BitsTransfer -Source $Source -Destination $Destination -ErrorAction Stop
            $StopLoop = $True
        }
        catch {
            if ($RetryCount -gt 4) {
                throw "Could not download $Source after 5 tries - error: " + $_
                $StopLoop = $True
            }
            else {
                Write-Log -Level Warn -Log "Failed to download file from $Source - retrying"
                Start-Sleep -Seconds 5
                $RetryCount = $RetryCount + 1
            }
        }
    }
    while ($StopLoop -eq $False)
}

Write-Log -Level Info -Log "Starting Script"

Write-Log -Level Info -Log "Checking if MDT is already installed"
$MDTInstalled = Get-WmiObject -Query "SELECT * FROM Win32_Product Where Name Like '%Microsoft Deployment Toolkit%'"
if ($MDTInstalled) {
    Write-Log -Level Error -Log "MDT is already installed. This script is for a clean Windows build. exiting"
    Exit-Script
}

# TODO: Check if ADK is already installed, if so, exit
Write-Log -Level Info -Log "Checking if ADK is already installed"
$ADKInstalled = Get-WmiObject -Query "SELECT * FROM Win32_Product Where Name Like '%Windows Deployment Tools%'"
if ($ADKInstalled) {
    Write-Log -Level Error -Log "ADK is already installed. This script is for a clean Windows build. exiting"
    Exit-Script
}

#Import configuration.ps1
Write-Log -Level Info -Log "Importing configuration.ps1"
$Configuration = Test-Path "$PSScriptRoot\configuration.ps1"
if (!$Configuration) {
    Write-Log -Level Error -Log "configuration.ps1 not found in script directory"
    Exit-Script
}

try {
    . "$PSScriptRoot\configuration.ps1"
}
catch {
    Write-Log -Level Error -Log "Check configuration.ps1 for syntax errors"
    Exit-Script
}

#Import applications.json and download Office Deployment Tool
if ($IncludeApplications) {
    Write-Log -Level Info -Log "Importing applications.json"
    $Applications = Test-Path "$PSScriptRoot\applications.json"
    if (!$Applications) {
        Write-Log -Level Error -Log "No applications.json file found in script directory"
        Exit-Script
    }
    else {
        try {
            $Applist = gc "$PSScriptRoot\applications.json" | ConvertFrom-Json
        }
        catch {
            Write-Log -Level Error -Log "Failed to load applications.json. Please check syntax and try again"
            Exit-Script
        }
    }
    New-Item -ItemType Directory -Path "$PSScriptRoot\odt" -Force | Out-Null
    try {
        Write-Log -Level Info -Log "Downloading Office Deployment Toolkit"
        Download-File -Source $OfficeDeploymentToolUrl -Destination "$PSScriptRoot\odt\officedeploymenttool.exe"
    } 
    catch {
        Write-Log -Level Error -Log "Failed to download Office Deployment Toolkit. ($($_))"
        Exit-Script
    }
}

Write-Log -Level Info -Log "Downloading MDT $MDTVersion"
$params = @{
    Source      = $MDTUrl
    Destination = "$PSScriptRoot\MicrosoftDeploymentToolkit_x64.msi"
}
try {
    Download-File @params -ErrorAction Stop
}
catch {
    Write-Log -Level Error -Log "Failed to download MDT. ($($_))"
    Exit-Script
}

Write-Log -Level Info -Log "Downloading ADK $ADKVersion"
$params = @{
    Source      = $ADKUrl
    Destination = "$PSScriptRoot\adksetup.exe"
}
try {
    Download-File @params -ErrorAction Stop
}
catch {
    Write-Log -Level Error -Log "Failed to download ADK. ($($_))"
    Exit-Script
}

Write-Log -Level Info -Log "Downloading ADK $ADKVersion WinPE Addon"
$params = @{
    Source      = $ADKWinPEUrl
    Destination = "$PSScriptRoot\adkwinpesetup.exe"
}
try {
    Download-File @params -ErrorAction Stop
}
catch {
    Write-Log -Level Error -Log "Failed to download ADK WinPE Addon. ($($_))"
    Exit-Script
}

Write-Log -Level Info -Log "Installing MDT $MDTVersion"
$params = @{
    Wait         = $True
    PassThru     = $True
    NoNewWindow  = $True
    FilePath     = "msiexec"
    ArgumentList = "/i ""$PSScriptRoot\MicrosoftDeploymentToolkit_x64.msi"" /qn " + 
    "/l*v ""$PSScriptRoot\mdt_install.log"""
}
$Return = Start-Process @params
if (@(0, 3010, 1641) -notcontains $Return.ExitCode) { 
    Write-Log -Level Error -Log "Failed to install MDT. Exit code: $($Return.ExitCode)"
    Exit-Script
}
$Return = $null

Write-Log -Level Info -Log "Installing ADK $ADKVersion"
$params = @{
    Wait         = $True
    PassThru     = $True
    NoNewWindow  = $True
    FilePath     = "$PSScriptRoot\adksetup.exe"
    ArgumentList = "/quiet /features OptionId.DeploymentTools " + 
    "/log ""$PSScriptRoot\adk.log"""
}
$Return = Start-Process @params
if ($Return.ExitCode -ne 0) {
    Write-Log -Level Error -Log "Failed to install ADK. Exit code: $($Return.ExitCode)"
    Exit-Script
}
$Return = $null

Write-Log -Level Info -Log "Installing ADK $ADKVersion WinPE Addon"
$params = @{
    Wait         = $True
    PassThru     = $True
    NoNewWindow  = $True
    FilePath     = "$PSScriptRoot\adkwinpesetup.exe"
    ArgumentList = "/quiet /features OptionId.WindowsPreinstallationEnvironment " +
    "/log ""$PSScriptRoot\adk_winpe.log"""
}
$Return = Start-Process @params
if ($Return.ExitCode -ne 0) {
    Write-Log -Level Error -Log "Failed to install ADK WinPE Addon. Exit code: $($Return.ExitCode)"
    Exit-Script
}
$Return = $null

Write-Log -Level Info -Log "Importing MDT Module"
$ModulePath = "$env:ProgramFiles\Microsoft Deployment Toolkit" +
"\bin\MicrosoftDeploymentToolkit.psd1"
Import-Module $ModulePath

Write-Log -Level Info -Log "Creating local Service Account for DeploymentShare"
$params = @{
    Name                 = "svc_mdt"      
    Password             = (ConvertTo-SecureString $SvcAccountPassword -AsPlainText -Force)
    AccountNeverExpires  = $true
    PasswordNeverExpires = $true
}
New-LocalUser @params

Write-Log -Level Info -Log "Creating Deployment Share Directory"
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
New-PSDrive @params | Add-MDTPersistentDrive 

Write-Log -Level Info -Log "Checking for wim files to import"
$Wims = Get-ChildItem $PSScriptRoot -Filter "*.wim" | Select -ExpandProperty FullName
if ($Wims) {
    foreach ($Wim in $Wims) {
        $WimName = (Split-Path $Wim -Leaf).TrimEnd(".wim")
        Write-Log -Level Info -Log "$WimName found - will import"
        $params = @{
            Path              = "DS001:\Operating Systems"
            SourceFile        = $Wim
            DestinationFolder = $WimName
        }
        $OSData = Import-MDTOperatingSystem @params | Out-Null
    }
} else {
    Write-Log -Level Info -Log "No WIM files found to import"
}

#Create Task Sequence for each Operating System
Write-Log -Level Info -Log "Creating Task Sequence for each imported Operating System"
$OperatingSystems = Get-ChildItem -Path "DS001:\Operating Systems"

if ($OperatingSystems) {
    [int]$counter = 0
    foreach ($OS in $OperatingSystems) {
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
        }
        Import-MDTTaskSequence @params | Out-Null
    }
}

#Edit Bootstrap.ini
$BootstrapIni = @"
[Settings]
Priority=Default
[Default]
DeployRoot=\\$env:COMPUTERNAME\DeploymentShare$
SkipBDDWelcome=YES
Userdomain=$env:COMPUTERNAME
UserID=svc_mdt
UserPassword=$SvcAccountPassword
"@

$params = @{
    Path  = "$DSDrive\DeploymentShare\Control\Bootstrap.ini"
    Value = $BootstrapIni
    Force = $True
}
Set-Content @params -Confirm:$False | Out-Null

#Edit CustomSettings.ini
$params = @{
    Path  = "$DSDrive\DeploymentShare\Control\CustomSettings.ini"
    Value = $CustomSettingsIni
    Force = $True
}
Set-Content @params -Confirm:$False | Out-Null

if ($DisableX86Support) {
    Write-Log -Level Info -Log "Disabling x86 Support"
    $DeploymentShareSettings = "$DSDrive\DeploymentShare\Control\Settings.xml"
    $xmldoc = [XML](Get-Content $DeploymentShareSettings)
    $xmldoc.Settings.SupportX86 = "False"
    $xmldoc.Save($DeploymentShareSettings)
}

#Create LiteTouch Boot WIM & ISO
Write-Log -Level Info -Log "Creating LiteTouch Boot Media"
Update-MDTDeploymentShare -Path "DS001:" -Force -Verbose | Out-Null

#download & Import Office 365 2016
if ($IncludeApplications) {
    Write-Log -Level Info -Log "Extracting Office Deployment Toolkit"
    $params = @{
        FilePath     = "$PSScriptRoot\odt\officedeploymenttool.exe"
        ArgumentList = "/quiet /extract:$PSScriptRoot\odt"
    }
    Start-Process @params -Wait
    Remove-Item "$PSScriptRoot\odt\officedeploymenttool.exe" -Force -Confirm:$false | Out-Null
    Set-Content -Path "$PSScriptRoot\odt\configuration.xml" -Value $Office365Configurationxml -Force -Confirm:$false | Out-Null
    Write-Log -Level Info -Log "Importing Office 365 into MDT"
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
    Import-MDTApplication @params | Out-Null
}

if ($IncludeApplications) {
    foreach ($Application in $AppList) {
        Write-Log -Level Info -Log "Downloading and importing $($Application.Name)"
        New-Item -Path "$PSScriptRoot\mdt_apps\$($application.name)" -ItemType Directory -Force | Out-Null
        $params = @{
            Source      = $Application.download
            Destination = "$PSScriptRoot\mdt_apps\$($application.name)\$($Application.filename)"
        }
        try {
            Download-File @params -ErrorAction Stop
            $params = @{
                Path                  = "DS001:\Applications"
                Name                  = $Application.Name
                ShortName             = $Application.Name
                Publisher             = ""
                Language              = ""
                Enable                = "True"
                Version               = $Application.version
                CommandLine           = $Application.install
                WorkingDirectory      = ".\Applications\$($Application.name)"
                ApplicationSourcePath = "$PSScriptRoot\mdt_apps\$($application.name)"
                DestinationFolder     = $Application.name
            }
            Import-MDTApplication @params | Out-Null
        }
        catch {
            Write-Log -Level Warn -Log "Failed to download $($Application.name). Check URL is valid in applications.json. ($($_))"
        }
    }
    Remove-Item -Path "$PSScriptRoot\mdt_apps" -Recurse -Force -Confirm:$false | Out-Null
}

#Install WDS
if ($InstallWDS) {
    $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($OSInfo.ProductType -eq 1) {
        Write-Log -Level Warn -Log "Workstation OS - WDS Not available"
    }
    else {
        Write-Log -Level Info -Log "Server OS - Checking if WDS available on this version"
        $WDSCheck = Get-WindowsFeature -Name WDS
        if ($WDSCheck) {
            Write-Log -Level Info -Log "WDS Role Available - Installing"
            Add-WindowsFeature -Name WDS -IncludeAllSubFeature -IncludeManagementTools | Out-Null
            $WDSInit = wdsutil /initialize-server /remInst:"$DSDrive\remInstall" /standalone
            $WDSConfig = wdsutil /Set-Server /AnswerClients:All
            $params = @{
                Path         = "$DSDrive\DeploymentShare\Boot\LiteTouchPE_x64.wim"
                SkipVerify   = $True
                NewImageName = "MDT Litetouch"
                
            }
            Import-WdsBootImage @params | Out-Null
        }
        else {
            Write-Log -Level Warn -Log "WDS Role not available on this version of Server"
        }
    }
}

#Finish
Write-Log -Level Info -Log "Script Finished"
Pause