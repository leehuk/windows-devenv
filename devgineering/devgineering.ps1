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
	[string]$Module  = "vm",
	[string]$Command = "help",

	# template provision
	[string]$BoxFile
)

enum VMStatus {
	NotCreated    = 0
	Unprovisioned = 1
	Provisioned   = 2
	Running       = 3
}

$VMName = "devgineering"
$VMMemory = (2*1024*1024*1024)
$VMCPU = 2

$VHDPath = "C:\HyperV\VHDs"
$TemplateVHDPath = "$VHDPath\devgineering-template.vhdx"
$TemplateInfoPath = "$VHDPath\devgineering-template.info"
$VMRootVHDPath = "$VHDPath\devgineering-root.vhdx"
$VMStoreVHDPath = "$VHDPath\devgineering-store.vhdx"

function display_help {
	Write-Host
	Write-Host "[devgineering] Dev VM Builder"
	Write-Host
	Write-Host " vm - Manage Virtual Machine"
	Write-Host
	Write-Host "   vm destroy         - Destroys the dev VM"
	Write-Host "   vm provision       - Provisions the dev VM"
	Write-Host "   vm start           - Start the dev VM"
	Write-Host "   vm status          - Show status of devgineering VM"
	Write-Host "   vm stop            - Stop the dev VM"
	Write-Host
	Write-Host " template - Manage VHD Template"
	Write-Host
	Write-Host "   template provision - Provision packer box to HyperV VHD template"
	Write-Host "                        Parameters: <-BoxFile /path/to/box>"
	Write-Host "   template status    - Show template VHD status"
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

	$provstatus = get_provisionstatus
	foreach($k in $provstatus.Keys) {
		if($provstatus[$k] -ne $True) {
			return [VMStatus]::Unprovisioned
		}
	}

	return [VMStatus]::Provisioned
}

function get_provisionstatus {
	$status = @{
		'BootOrder'			= $False
		'CPUCount'			= $False
		'DiskRoot'          = $False
		'DiskRootAttached'  = $False
		'DiskStore'         = $False
		'DiskStoreAttached' = $False
		'SecureBoot'		= $False
	}

	$vm = Get-VM -Name $VMName -ErrorAction Ignore
	if(-Not $vm) {
		return $status
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

	return $status
}


if($Module -eq 'vm') {
	if($Command -eq "destroy") {
		$status = get_vmstatus
		if($status -le [VMStatus]::NotCreated) {
			Write-Host "$VMName is $status"
			exit
		}

		$confirm = Read-Host "This will permanently *DESTROY* the VM and its root hard disk.  Enter YES to continue"
		if($confirm -eq "YES") {
			Get-VMHardDiskDrive $VMName | Remove-VMHardDiskDrive
			Remove-Item $VMRootVHDPath -ErrorAction Ignore
			Remove-VM $VMName -Force
		} else {
			Write-Host "Aborted"
		}
	} elseif($Command -eq "provision") {
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

		if($status -lt [VMStatus]::Provisioned) {
			$provstatus = get_provisionstatus

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
	# vm status
	} elseif($Command -eq 'status') {
		$status = get_vmstatus
		Write-Host "$VMName is $status"
	# vm start
	} elseif($Command -eq 'start') {
		$status = get_vmstatus
		if($status -lt [VMStatus]::Provisioned) {
			Write-Error "$VMName is not provisioned"
			exit
		}

		Start-VM $VMName
	# vm stop
	} elseif($Command -eq 'stop') {
		$status = get_vmstatus
		if($status -lt [VMStatus]::Running) {
			Write-Error "$VMName is not running"
			exit
		}

		Stop-VM $VMName
	} else {
		display_help
	}
} elseif($Module -eq 'template') {
	# template provision
	if($Command -eq "provision") {
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

		# The packer box files are tar.gz, we need 7zip to extract them
		if (-Not (Get-Command Expand-7Zip -ErrorAction Ignore)) {
			Install-Package -Scope CurrentUser -Force 7Zip4PowerShell
		}

		$temppath = "$env:TEMP\devgineering"
		$tempvhdpath = "$temppath\Virtual Hard Disks"

		# The first extract gives us the tar file, the second the actual contents
		Expand-7zip $BoxFile "$temppath"

		$files = Get-Item "$temppath\*.tar" -ErrorAction Ignore
		if($files.Count -ne 1) {
			Write-Error "Unable to find exactly one tar file in $temppath"
			exit
		}

		$tarpath = $temppath + "\" + $files[0].Name
		Expand-7zip "$tarpath" "$temppath"

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
	} elseif($Command -eq "status") {
		$template = Get-Item "$TemplateVHDPath" -ErrorAction Ignore
		if($template) {
			Write-Host "devgineering-template Provisioned"
			Write-Host "Last Modified:"$template.LastWriteTime

			$info = Get-Item "$TemplateInfoPath" -ErrorAction Ignore
			if($info) {
				Get-Content $info
			}
		} else {
			Write-Host "devgineering-template Unprovisioned"
		}
	} else {
		display_help
	}
} else {
	display_help
}
