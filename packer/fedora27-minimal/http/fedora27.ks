# Basic commands
install
reboot
text
url --url=https://mirror.bytemark.co.uk/fedora/linux/releases/27/Everything/x86_64/os/
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
rootpw --iscrypted $6$JjiD8//K4owApakd$j1QFDYJYkNLKMohgZxaMeowvFzzbDV7QlhpK4s5YR41htsLYRW6WOnP8FlTPTc8OHGiQZm5SdUvOHeICVaTd2.
user --name=vagrant --password=$6$idMvtY6Ik6qh9FR6$UmAYRxza5NWCZmo35MvJ/lcVJ8/B5nGNOVV1jOy3Mux6A/z8yGoiXrrxa7UFzodkQdjK1y9VTdPNN.0B97pQU/ --iscrypted --gecos="vagrant"
# System bootloader configuration
bootloader --location=mbr
# Partition clearing information
clearpart --none --initlabel
# Disk partitioning information
part /boot/efi --fstype="efi" --ondisk=sda --size=256 --fsoptions="umask=0077,shortname=winnt"
part /boot --fstype="xfs" --ondisk=sda --size=256
part pv.406 --fstype="lvmpv" --ondisk=sda --grow
volgroup vg0 --pesize=4096 pv.406
logvol /var/log  --fstype="xfs" --size=64 --name=log --vgname=vg0
logvol /  --fstype="xfs" --size=4096 --name=root --vgname=vg0

%packages
@core --nodefaults
virt-what
-audit
-firewalld
-GeoIP
-iproute-tc
-kpartx
-linux-firmware
-NetworkManager
-pigz
-pinentry
-polkit
-selinux-policy
-sssd-client
-trousers
%end

%addon com_redhat_kdump --disable --reserve-mb='128'
%end

%post
# HyperV Integration
if [ $(virt-what) == "hyperv" ]; then
  dnf install -y hyperv-daemons
  systemctl enable hypervkvpd cifs-utils
fi

# There appears to be a bug in anaconda, meaning recommends are taking
# priority over the removals specified in %packages:
# https://bugzilla.redhat.com/show_bug.cgi?id=1412398
#
# Forcibly remove the packages we dont want as the last dnf stage, as
# the removal appears to block other installations
dnf remove -y audit firewalld GeoIP iproute-tc kpartx linux-firmware NetworkManager pigz pinentry polkit selinux-policy sssd-client trousers

dnf clean all

# Enable the basic networking initialisation in place of networkmanager
chkconfig network on

# Grant vagrant sudo privs
echo "vagrant ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/vagrant
%end
