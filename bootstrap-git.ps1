## bootstrap-git.ps1
## Second stage bootstrapping of github.
##
## Generates and outputs ecdsa ssh keys, sets the ssh config for github to
## use them and then clones the windows-devenv repo ready to complete
## the bootstrapping process.

$Home -Match "^([A-Z]):(.*)" | Out-Null

if(-Not $Matches[1] -Or -Not $Matches[2]) {
    Write-Error "Unable to determine home path"
    Read-Host -Prompt "Press Enter to continue"
}

$HomeUnixPath = ("/" + $Matches[1].ToLower() + $Matches[2].Replace('\','/'))
$VendorPath = "C:\tools\cmder\vendor"
$SshConfigPath = ($Home + "\.ssh\config")
$SshKeyPath = ($Home + "\.ssh\id_git")
$GitWorkPath = ("\git")

$gitfile = Get-Item $SshKeyPath -ErrorAction SilentlyContinue
if($gitfile -eq $null) {
    $sshkeyfile = ($HomeUnixPath + "/.ssh/id_git")
    Invoke-Expression ($VendorPath + "\git-for-windows\usr\bin\ssh-keygen.exe -t ecdsa -f " + $sshkeyfile)
    
    Write-Host "Public key for github:"
    Get-Content ($SshKeyPath + ".pub")

    Write-Host
    Write-Host "To proceed, your sshkey must be present on github"
    Read-Host -Prompt "Press Enter to continue"
}

$sshconfigfile = Get-Item $SshConfigPath -ErrorAction SilentlyContinue
if($sshconfigfile -eq $null -Or (Select-String "github.com" $SshConfigPath) -eq $null) {
    Add-Content $SshConfigPath ("Host github.com`n`tUser leehuk`n`tIdentityFile " + $HomeUnixPath + "/.ssh/id_git")
}

$gitworkdir = Get-Item $GitWorkPath -ErrorAction SilentlyContinue
if($gitworkdir -eq $null) {
    New-Item -Path $Home -Name "git" -ItemType "directory"
}

Set-Location $GitWorkPath
git clone git@github.com:leehuk/windows-devenv.git
