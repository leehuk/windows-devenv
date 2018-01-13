## tasks/vagrant.ps1
## Vagrant Installation
##
## Installs Vagrant

# If we do not have elevated privs, obtain them
if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { 
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit 
}

choco install vagrant

vagrant plugin install vagrant-reload
