# Basic commands
install
reboot
text
url --url=https://mirror.bytemark.co.uk/fedora/linux/releases/31/Everything/x86_64/os/
repo --name updates
# System authorization information
auth --enableshadow --passalgo=sha512
ignoredisk --only-use=sda
selinux --disabled
# Localisation
keyboard --vckeymap=gb --xlayouts='gb'
lang en_GB.UTF-8
timezone Europe/London --isUtc
# Network information
network  --bootproto=dhcp --device=eth0 --ipv6=auto --activate
network  --hostname=localhost.localdomain
# User accounts
rootpw --iscrypted $6$iL9oY8UPc/SDxuWS$R5v49hItg1u0MSL6FCU.EmjGhiQ8fwTUjoI.Hq8wkSI6cjIj/foSyOeMCCpgBn1k/vmn4sBlawIjm7Trav.SV.
user --name=packer --password=$6$aONeZ7dNk85m7LsR$c7QfV6mYwZspARbNSvODTlxP2imeDW3GymcV9/KBPad1AzQn5tHMU2JKGrqtYq4jjR4spe/SaXp36dqvp95dG0 --iscrypted --gecos="packer"
# System bootloader configuration
bootloader --location=mbr
# Partition clearing information
clearpart --none --initlabel
# Disk partitioning information
part /boot/efi --fstype="efi" --ondisk=sda --size=256 --fsoptions="umask=0077,shortname=winnt"
part /boot --fstype="xfs" --ondisk=sda --size=256
part pv.406 --fstype="lvmpv" --ondisk=sda --grow
volgroup vg_root --pesize=4096 pv.406
logvol /var/log  --fstype="xfs" --size=128 --name=log --vgname=vg_root
logvol /  --fstype="xfs" --size=3072 --name=root --vgname=vg_root

%packages
@core --nodefaults
tar
vim
virt-what
%end

%addon com_redhat_kdump --disable --reserve-mb='128'
%end

%post
# HyperV Integration
if [ $(virt-what) == "hyperv" ]; then
  dnf install -y hyperv-daemons cifs-utils
  systemctl enable hypervkvpd
fi

# There appears to be a bug in anaconda, meaning recommends are taking
# priority over the removals specified in %packages:
# https://bugzilla.redhat.com/show_bug.cgi?id=1412398
#
# Forcibly remove the packages we dont want as the last dnf stage, as
# the removal appears to block other installations
#dnf remove -y audit firewalld GeoIP iproute-tc kpartx linux-firmware NetworkManager pigz pinentry polkit selinux-policy sssd-client trousers

dnf clean all

# Enable the basic networking initialisation in place of networkmanager
chkconfig network on

# Grant packer sudo privs
echo "packer ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/packer
%end
