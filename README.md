# MDT-Auto-Deployment

Microsoft Deployment Toolkit Auto-Deployment PowerShell Script v3.4

**Warning: This script is intended to run on a clean Windows installation which doesn’t have MDT/ADK installed/configured already. Unexpected results will arise when running on already configured deployment servers.**

Tested on Windows 10 1607, Server 2016 & 2019

## How to use
1) Download: https://github.com/pwshMgr/MDT-Auto-Deployment/archive/3.4.zip
2) Add your desired WIM files that you wish to auto import in the same folder where the script resides
3) Add any additonal applications to be imported to applications.json
4) Modify configuration.ps1 if required
5) Run with the below command:

```powershell
powershell -ExecutionPolicy Bypass -File mdt-auto-deployment.ps1 -IncludeApplications -InstallWds
```
You will be asked to enter the following information:
- ServiceAccountPassword – password for the local service account that gets created when the script runs
- DeploymentShareDrive – select which drive you want the deployment share to exist on, i.e. c:\

## Tasks the script completes
1) Download & install MDT (8456) & ADK (1809)
2) Creates a local user with the account name “svc_mdt” (for Read-Only DeploymentShare access)
3) Creates a new Deployment Share
4) Imports all WIM files placed in the script folder
5) Creates a standard client task sequence for each WIM image found
6) Edits bootstrap.ini with the Deployment Share access information
7) Edits CustomSettings.ini with data from configuration.ps1
8) Disables x86 support if set to $true in configuration.ps1 (saves time when regenerating boot images)
9) Creates Boot media
10) OPTIONAL - Installs and configures WDS and imports boot file (include -InstallWds switch)
11) OPTIONAL – Imports the following 64bit applications into MDT (include -IncludeApplications switch):
- Google Chrome Enterprise
- Mozilla Firefox
- 7-Zip
- Visual Studio Code
- Node.js
- MongoDB Community
- VLC Media Player
- Treesize Free
- Putty
- Office 365 monthly build