# devgineering.ps1
# Powershell script automating provisioning a Dev VM from a packer image.
#
# Copyright (C) 2018 Lee H <lee@leeh.uk>
# Licensed under the BSD 2-Clause License as found in LICENSE.txt

# This script is a wrapper to jump from a packer image to a HyperV VM without
# needing to use vagrant.  Largely built for a requirement to have a second
# disk attached to the VM thats persistent, allowing the main OS to be rebuilt
# from updated packer images -- without losing git repos etc.

param (
	[string]$Module  = "help",

	# template provision
	[string]$BoxFile
)

enum VMStatus {
	NotCreated    = 0
	Created		  = 1
	Configured    = 2
	Running       = 3
	Provisioned   = 4
}

$VMName = "devgineering"
$VMMemory = (2*1024*1024*1024)
$VMCPU = 2

$VHDPath = "C:\HyperV\VHDs"
$TemplateVHDPath = "$VHDPath\devgineering-template.vhdx"
$TemplateInfoPath = "$VHDPath\devgineering-template.info"
$VMRootVHDPath = "$VHDPath\devgineering-root.vhdx"
$VMStoreVHDPath = "$VHDPath\devgineering-store.vhdx"

$SSHKeyFolder = "C:\HyperV\packer.ssh"
$SSHKeyFile = "$SSHKeyFolder\id_ed25519"
$SSHKeyPubFile = "$SSHKeyFile.pub"

function display_help {
	Write-Host
	Write-Host "[devgineering] Dev VM Builder"
	Write-Host
	Write-Host " status          - Show Status Information"
	Write-Host
	Write-Host " up              - Provision Environment"
	Write-Host " stop            - Stop VM"
	Write-Host " destroy         - Destroy VM"
	Write-Host " ssh             - SSH to VM"
	Write-Host
	Write-Host " templatesync    - Provision VHD Template"
	Write-Host
	Write-Host " help - This help"
	Write-Host
}

function get_vmexist {
	$vm = Get-VM -Name $VMName -ErrorAction Ignore
	if($vm) {
		return $True
	}
	return $False
}

function get_vmstatus {
	$vm = Get-VM -Name $VMName -ErrorAction Ignore
	if(-Not $vm) {
		return [VMStatus]::NotCreated
	}

	if($vm.State -eq 'Running') {
		return [VMStatus]::Running
	}

	$provstatus = get_vmconfig
	foreach($k in $provstatus.Keys) {
		if($provstatus[$k] -ne $True) {
			return [VMStatus]::Created
		}
	}

	return [VMStatus]::Configured
}

function get_vmconfig {
	$status = @{
		'BootOrder'			= $False
		'Checkpoints'		= $False
		'CPUCount'			= $False
		'DiskRoot'          = $False
		'DiskRootAttached'  = $False
		'DiskStore'         = $False
		'DiskStoreAttached' = $False
		'NicCount'			= $False
		'SecureBoot'		= $False
	}

	if(-Not (get_vmexist)) {
		return $status
	}

	if((Get-VM $VMName).CheckpointType -eq "Disabled") {
		$status['Checkpoints'] = $True
	}
	if((Get-Item $VMRootVHDPath -ErrorAction Ignore)) {
		$status['DiskRoot'] = $True
	}

	if((Get-Item $VMStoreVHDPath -ErrorAction Ignore)) {
		$status['DiskStore'] = $True
	}

	foreach($harddisk in (Get-VMHardDiskDrive $VMName)) {
		if($harddisk.Path -eq $VMRootVHDPath) {
			$status['DiskRootAttached'] = $True
		} elseif($harddisk.Path -eq $VMStoreVHDPath) {
			$status['DiskStoreAttached'] = $True
		}
	}

	$bootorder = (Get-VMFirmware $VMName).BootOrder
	if($bootorder.Count -eq 1 -And $bootorder[0].BootType -eq "Drive" -And $bootorder[0].Device.Path -eq $VMRootVHDPath) {
		$status['BootOrder'] = $True
	}

	if((Get-VMFirmware $VMName).SecureBoot -eq 'Off') {
		$status['SecureBoot'] = $True
	}

	if((Get-VMProcessor $VMName).Count -eq $VMCPU) {
		$status['CPUCount'] = $True
	}

	if(($vm.NetworkAdapters).Count -eq 1) {
		$status['NICCount'] = $True
	}

	return $status
}

function get_vminfo {
	$status = @{
		'IPAddress'	= $False
	}

	if(-Not (get_vmexist)) {
		return $status
	}

	$vmnic = (Get-VM -Name $VMName).NetworkAdapters
	($vmnic).IPAddresses | Foreach-Object -Process {
		if($_ -Match "^172.31.255.") {
			$status['IPAddress'] = $_
		}
	}

	return $status
}

function provision_vm {
	$status = get_vmstatus
	if($status -le [VMStatus]::NotCreated) {
		try {
			New-VM -Name $VMName -MemoryStartupBytes $VMMemory -Generation 2 -BootDevice VHD -SwitchName HyperV-NAT -ErrorAction stop | Out-Null
		} catch {
			Write-Error "Unable to create VM"
			throw
		}
	}

	$template = Get-Item "$TemplateVHDPath" -ErrorAction Ignore
	if(-Not $template) {
		Write-Error "Template is not provisioned"
		exit
	}

	$provstatus = get_vmconfig

	# Ensure checkpoints are disabled
	if(-Not $provstatus['Checkpoints']) {
		Set-VM $VMName -CheckpointType Disabled
	}

	# Provision our root disk file, by cloning the template.
	if(-Not $provstatus['DiskRoot']) {
		Import-Module BitsTransfer
		Start-BitsTransfer -Source "$TemplateVHDPath" -Destination "$VMRootVHDPath" -Description "Cloning VHDX" -DisplayName "Cloning VHDX"
	}

	# Provision a new storage drive.  This will only ever be done once.
	if(-Not $provstatus['DiskStore']) {
		New-VHD -Path "$VMStoreVHDPath" -SizeBytes 20GB | Out-Null
	}

	if(-Not $provstatus['DiskRootAttached']) {
		Add-VMHardDiskDrive $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $VMRootVHDPath
	}

	if(-Not $provstatus['DiskRootAttached']) {
		Add-VMHardDiskDrive $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $VMStoreVHDPath
	}

	if(-Not $provstatus['BootOrder']) {
		$bootdevice =  Get-VMHardDiskDrive devgineering -ControllerNumber 0 -ControllerLocation 0
		Set-VMFirmware $VMName -BootOrder $bootdevice
	}

	if(-Not $provstatus['SecureBoot']) {
		Set-VMFirmware $VMName -EnableSecureBoot Off
	}

	if(-Not $provstatus['CPUCount']) {
		Set-VMProcessor $VMName -Count $VMCPU
	}
}

function provision_ssh {
	if(-Not (Get-Item $SSHKeyFolder -ErrorAction Ignore)) {
		New-Item $SSHKeyFolder -ItemType Directory | Out-Null
	}

	if(-Not (Get-Item $SSHKeyFile -ErrorAction Ignore)) {
		ssh-keygen -q -t ed25519 -f $SSHKeyFile -N '""'
	}

	if(-Not (Get-Item $SSHKeyPubFile -ErrorAction Ignore)) {
		Write-Host "devgineering-vm: Error: Found private key file, but missing public key file"
		return
	}

	if((Get-Item $SSHKeyPubFile | Get-Content).Count -ne 1) {
		Write-Host "devgineering-vm: Error: Public key file has multiple lines"
		return
	}

	$info = get_vminfo
	if(-Not $info['IPAddress'] -Match '^172.31.255.[0-9]+') {
		Write-Host "devgineering-vm: Error: Invalid IP Address:", $info['IPAddress']
		return
	}

	$result = $(ssh -i $SSHKeyFile -o StrictHostKeyChecking=false,PreferredAuthentications=publickey -l packer $info['IPAddress'] whoami 2>&1)
	if($result -ne "packer") {
		Write-Host "devgineering-vm: SSH Setup Required"
		Write-Host "When prompted for a password, enter 'packer'"

		$pubkey = (Get-Item $SSHKeyPubFile | Get-Content)
		ssh -l packer $info['IPAddress'] "mkdir -p .ssh && chmod 700 .ssh && echo '$pubkey' > .ssh/authorized_keys && chmod 600 .ssh/authorized_keys"
	}
}

function run_status {
	$template = Get-Item "$TemplateVHDPath" -ErrorAction Ignore
	if($template) {
		Write-Host "devgineering-template: Provisioned"

		if(($content = Get-Item "$TemplateInfoPath" -ErrorAction Ignore | Get-Content)) {
			Write-Host "devgineering-template: $content"
		}
	} else {
		Write-Host "devgineering-template: Created"
	}

	$status = get_vmstatus
	Write-Host "devgineering-vm: $status"

	if($status -ge [VMStatus]::Running) {
		$info = get_vminfo
		Write-Host "devgineering-vm: IP", $info['IPAddress']
	}

	$provstatus = get_vmconfig
	$status = ''
	foreach($k in $provstatus.Keys) {
		$v = $provstatus[$k]
		$status = "$status $k=$v"
	}

	Write-Host "devgineering-vm:$status"
}

function run_ssh {
	$vminfo = get_vminfo
	ssh -i $SSHKeyFile -o PreferredAuthentications=publickey -l packer $vminfo['IPAddress']
}

if($Module -eq 'status') {
	run_status
} elseif($Module -eq 'destroy') {
	$status = get_vmstatus
	if($status -le [VMStatus]::NotCreated) {
		exit
	}

	if($status -ge [VMStatus]::Running) {
		Stop-VM $VMName
	}

	$confirm = Read-Host "This will permanently *DESTROY* the VM and its root hard disk.  Enter YES to continue"
	if($confirm -eq "YES") {
		Get-VMHardDiskDrive $VMName | Remove-VMHardDiskDrive
		Remove-Item $VMRootVHDPath -ErrorAction Ignore
		Remove-VM $VMName -Force
	} else {
		Write-Host "Aborted"
	}
} elseif($Module -eq 'stop') {
	$status = get_vmstatus
	if($status -lt [VMStatus]::Running) {
		exit
	}

	Stop-VM $VMName
} elseif($Module -eq 'up') {
	provision_vm

	$status = get_vmstatus
	if($status -lt [VMStatus]::Configured) {
		Write-Warning "devgineering-vm: Not Configured Correctly"

		$provstatus = get_vmconfig
		foreach($k in $provstatus.Keys) {
			if($provstatus[$k] -ne $True) {
				Write-Warning "devgineering-vm: $k Incorrect"
			}
		}

		$confirm = Read-Host "Enter YES to continue"
		if($confirm -ne "YES") {
			exit
		}
	}

	if($status -lt [VMStatus]::Running) {
		Start-VM $VMName

		Write-Progress "Waiting for IP Address" -SecondsRemaining 120
		# We wait here until the VM has bound an IP address
		for($i = 24; $i -gt 0; $i--) {
			$vminfo = get_vminfo
			if($vminfo['IPAddress']) {
				break
			}

			Start-Sleep -Seconds 5
			Write-Progress "Waiting for IP Address" -SecondsRemaining ($i*5)
		}

		# Give ssh a few seconds
		Start-Sleep -Seconds 5
		Write-Progress "Waiting for IP Address" -Completed
	}

	provision_ssh
} elseif($Module -eq 'templatesync') {
	if(-Not $BoxFile) {
		Write-Error "-BoxFile not specified"
		exit
	}

	$boxinfo = Get-Item $BoxFile -ErrorAction Ignore
	if(-Not $boxinfo) {
		Write-Error "$BoxFile not found"
		exit
	}

	# Cleanup existing template files
	if((Get-Item "$TemplateVHDPath" -ErrorAction Ignore)) {
		Remove-Item "$TemplateVHDPath"
	}

	if((Get-Item "$TemplateInfoPath" -ErrorAction Ignore)) {
		Remove-Item "$TemplateInfoPath"
	}

	$temppath = "$env:TEMP\devgineering"
	$tempvhdpath = "$temppath\build\Virtual Hard Disks"

	if((Get-Item "$temppath" -ErrorAction Ignore)) {
		Remove-Item "$temppath"
	}

	# The first extract gives us the tar file, the second the actual contents
	Expand-Archive $BoxFile -DestinationPath "$temppath"

	$files = Get-Item "$tempvhdpath\*.vhdx" -ErrorAction Ignore
	if($files.Count -ne 1) {
		Write-Error "Unable to find exactly one VHDX file in $tempvhdpath"
	}

	# We have our VHDX file, lets move it over and add some info
	$diskpath = $tempvhdpath + "\" + $files[0].Name
	Move-Item "$diskpath" "$TemplateVHDPath"

	$infotext = "From $BoxFile at " + $boxinfo.LastWriteTime
	New-Item -Path "$VHDPath" -Name "devgineering-template.info" -Value "$infotext" | Out-Null

	# Cleanup temporary path
	Remove-Item -Recurse "$temppath"
} elseif($Module -eq "ssh") {
	$status = get_vmstatus
	if($status -lt [VMStatus]::Running) {
		Write-Host "devgineering-vm: Not Running"
		exit
	}

	run_ssh
} else {
	display_help
}
