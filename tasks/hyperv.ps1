## tasks/hyperv.ps1
## Hyper-V Installation
##
## Installs Hyper-V, setting up NAT network along the way

# If we do not have elevated privs, obtain them
if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { 
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit 
}

Write-Host "Checking Microsoft-Hyper-V Feature"
$install = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
if(-Not $install -Or $install.State -ne "Enabled") {
	Write-Host "Enabling Microsoft-Hyper-V Feature"
	$hyperv = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -NoRestart
}

Write-Host "Checking Microsoft-Hyper-V-Management-Clients Feature"
$install = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-Clients
if(-Not $install -Or $install.State -ne "Enabled") {
	Write-Host "Enabling Microsoft-Hyper-V-Management-Clients Feature"
	$hypervgui = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-Clients -NoRestart
}

Write-Host "Checking Microsoft-Hyper-V-Management-PowerShell Feature"
$install = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell
if(-Not $install -Or $install.State -ne "Enabled") {
	Write-Host "Enabling Microsoft-Hyper-V-Management-PowerShell Feature"
	$hypervps = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -NoRestart
}

if($hyperv.RestartNeeded -Or $hypervgui.RestartNeeded -Or $hypervps.RestartNeeded) {
	Write-Host "Restart is required due to Hyper-V installation"
	Restart-Computer -Confirm
}

Write-Host "Checking for HyperV-NAT Switch"
try {
	Get-VMSwitch -Name "HyperV-NAT" -ErrorAction Stop | Out-Null
	Write-Host "Found HyperV-NAT Switch"
} catch {
	Write-Host "Creating HyperV-NAT Switch"
	New-VMSwitch -SwitchName "HyperV-NAT” -SwitchType Internal | Out-Null
}

Write-Host "Checking for NAT Network"
try {
	Get-NetIPAddress -IPAddress 172.31.255.254 -PrefixLength 24 -InterfaceAlias "vEthernet (HyperV-NAT)" -ErrorAction Stop | Out-Null
	Write-Host "Found NAT Network"
} catch {
	Write-Host "Creating NAT Network"
	New-NetIPAddress -IPAddress 172.31.255.254 -PrefixLength 24 -InterfaceAlias “vEthernet (HyperV-NAT)” | Out-Null
}

Write-Host "Checking for Hyper-V NAT"
try {
	Get-NetNat -Name "HyperV-NAT" -ErrorAction Stop | Out-Null
	Write-Host "Found Hyper-V NAT"
} catch {
	Write-Host "Creating Hyper-V NAT"
	New-NetNAT -Name "HyperV-NAT" -InternalIPInterfaceAddressPrefix 172.31.255.0/24
}
