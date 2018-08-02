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
	New-VMSwitch -SwitchName "HyperV-NAT" -SwitchType Internal | Out-Null
}

Write-Host "Checking for NAT Network"
try {
	Get-NetIPAddress -IPAddress 172.31.255.254 -PrefixLength 24 -InterfaceAlias "vEthernet (HyperV-NAT)" -ErrorAction Stop | Out-Null
	Write-Host "Found NAT Network"
} catch {
	Write-Host "Creating NAT Network"
	New-NetIPAddress -IPAddress 172.31.255.254 -PrefixLength 24 -InterfaceAlias "vEthernet (HyperV-NAT)" | Out-Null
}

Write-Host "Checking for Hyper-V NAT"
try {
	Get-NetNat -Name "HyperV-NAT" -ErrorAction Stop | Out-Null
	Write-Host "Found Hyper-V NAT"
} catch {
	Write-Host "Creating Hyper-V NAT"
	New-NetNAT -Name "HyperV-NAT" -InternalIPInterfaceAddressPrefix 172.31.255.0/24
}

Write-Host "Checking for HyperV Storage Folder"
try {
	Get-Item "C:\HyperV" -ErrorAction stop | Out-Null
	Write-Host "Found C:\HyperV"

	if(-Not ((Get-Item C:\HyperV) -is [System.IO.DirectoryInfo])) {
		Write-Host "C:\HyperV is not a directory, removing"
		Remove-Item C:\HyperV

		Write-Host "Creating C:\HyperV"
		New-Item -Path C:\ -Name "HyperV" -ItemType "directory"
	}
} catch {
	Write-Host "Creating C:\HyperV"
	New-Item -Path C:\ -Name "HyperV" -ItemType "directory"
}

Write-Host "Checking for HyperV Storage VHD Folder"
try {
	Get-Item "C:\HyperV\VHDs" -ErrorAction stop | Out-Null
	Write-Host "Found C:\HyperV\VHDs"
} catch {
	Write-Host "Creating C:\HyperV\VHDs"
	New-Item -Path C:\HyperV -Name "VHDs" -ItemType "directory"
}

Write-Host "Looking up account information"
$UserIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$UserIdentityName = $UserIdentity.Name
$UserAccount = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList $UserIdentityName

$WorkPath = "C:\HyperV"
Write-Host "Checking ownership of $WorkPath"
$ACL = Get-ACL $WorkPath
if($ACL.Owner -ne $UserIdentityName) {
	Write-Host "Changing ownership of $WorkPath"
	$ACL.SetOwner($UserAccount)
	Set-ACL $WorkPath -AclObject $ACL
}

$WorkPath = "C:\HyperV\VHDs"
Write-Host "Checking ownership of $WorkPath"
$ACL = Get-ACL $WorkPath
if($ACL.Owner -ne $UserIdentityName) {
	Write-Host "Changing ownership of $WorkPath"
	$ACL.SetOwner($UserAccount)
	Set-ACL $WorkPath -AclObject $ACL
}

$WorkPath = "C:\HyperV"
Write-Host "Checking permissions of $WorkPath"
$ACL = Get-ACL $WorkPath

$AccessFoundUser = $False
$AccessFoundSystem = $False
$AccessFoundOther = $False

foreach($Access in $ACL.Access) {
	if($Access.FileSystemRights -eq "FullControl" -And $Access.IdentityReference -eq $UserIdentityName) {
		$AccessFoundUser = $True
	} elseif($Access.FileSystemRights -eq "FullControl" -And $Access.IdentityReference -eq "NT AUTHORITY\SYSTEM") {
		$AccessFoundSystem = $True
	} else {
		$AccessFoundOther = $True
	}
}

if($AccessFoundOther -Or -Not $AccessFoundUser -Or -Not $AccessFoundSystem) {
	Write-Host "Resetting permissions on $WorkPath"

	# Clear Inheritance
	$ACL.SetAccessRuleProtection($True, $True)

	foreach($Access in $ACL.Access) {
		$ACL.RemoveAccessRule($Access)
	}

	$AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($UserIdentityName, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
	$ACL.SetAccessRule($AccessRule)

	$AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule('SYSTEM', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
	$ACL.SetAccessRule($AccessRule)

	Set-ACL $WorkPath -AclObject $ACL
}

Write-Host "Checking HyperV VHD Directory"
if((Get-VMHost).VirtualHardDiskPath -ne "C:\HyperV\VHDs") {
	Write-Host "Setting HyperV VHD Directory"
	Set-VMHost -VirtualHardDiskPath "C:\HyperV\VHDs"
}
