## bootstrap-choco.ps1
## First stage bootstrapping of choco, sudo, cmder and curl
##
## Installs chocolatey, a sudo wrapper and then uses chocolatey
## to install cmder and curl.  Cmder brings with it a chunk of Linux
## userland together with Git, providing a more accesible dev environment.

# If we do not have elevated privs, obtain them
if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { 
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit 
}

if((Get-Command "choco.exe" -ErrorAction SilentlyContinue) -eq $null) { 
    if((Get-ExecutionPolicy) -eq "Restricted") { 
        Set-ExecutionPolicy Bypass -Scope Process -Force
    }

    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

if((Get-Command "sudo.exe" -ErrorAction SilentlyContinue) -eq $null) {
    $sudoziploc = [System.IO.Path]::GetTempFileName() + ".zip"
    (New-Object System.Net.WebClient).DownloadFile("https://github.com/mattn/sudo/releases/download/v0.0.1/sudo-x86_64.zip", $sudoziploc)

    $unpackloc = [System.IO.Path]::GetTempFileName()
    Remove-Item $unpackloc
    $unpackname = Split-Path $unpackloc -Leaf
    New-Item -Path ([System.IO.Path]::GetTempPath()) -Name $unpackname -ItemType "directory"

    Expand-Archive $sudoziploc -DestinationPath $unpackloc

    Move-Item ($unpackloc + "\sudo.exe") -Destination "C:\ProgramData\chocolatey\bin\sudo.exe"

    Remove-Item $sudoziploc
    Remove-Item $unpackloc
}

choco install cmder
choco install curl

Read-Host -Prompt "Press Enter to continue"
