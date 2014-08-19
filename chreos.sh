# This is a modified version of jay0lee's Chrubuntu. Check out his cool work at https://github.com/jay0lee/chrubuntu-script
# The file you are looking at right now is based on his older version, which you can find here: http://goo.gl/s9ryd
# Original release blogpost: http://chromeos-cr48.blogspot.de/search?updated-max=2013-06-26T08:52:00-04:00&max-results=3
# Like this? Do ahead and donate a few bucks to jay0lee (link above)

# fw_type will always be developer for Mario.
# Alex and ZGB need the developer BIOS installed though.
fw_type="`crossystem mainfw_type`"
if [ ! "$fw_type" = "developer" ]
  then
    echo -e "\nYou're Chromebook is not running a developer BIOS!"
    echo -e "You need to run:"
    echo -e ""
    echo -e "sudo chromeos-firmwareupdate --mode=todev"
    echo -e ""
    echo -e "and then re-run this script."
    exit
fi

powerd_status="`initctl status powerd`"
if [ ! "$powerd_status" = "powerd stop/waiting" ]
then
  echo -e "Stopping powerd to keep display from timing out..."
  initctl stop powerd
fi

setterm -blank 0

if [ "$3" != "" ]; then
  target_disk=$3
  echo "Got ${target_disk} as target drive"
  echo ""
  echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
  echo ""
  read -p "Press [Enter] to install ElementaryOS on ${target_disk} or CTRL+C to quit"

  ext_size="`blockdev --getsz ${target_disk}`"
  aroot_size=$((ext_size - 65600 - 33))
  parted --script ${target_disk} "mktable gpt"
  cgpt create ${target_disk}
  cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
  cgpt add -i 7 -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
  sync
  blockdev --rereadpt ${target_disk}
  partprobe ${target_disk}
  crossystem dev_boot_usb=1
else
  target_disk="`rootdev -d -s`"
  # Do partitioning (if we haven't already)
  ckern_size="`cgpt show -i 6 -n -s -q ${target_disk}`"
  croot_size="`cgpt show -i 7 -n -s -q ${target_disk}`"
  state_size="`cgpt show -i 1 -n -s -q ${target_disk}`"

  max_ubuntu_size=$(($state_size/1024/1024/2))
  rec_ubuntu_size=$(($max_ubuntu_size - 1))
  # If KERN-C and ROOT-C are one, we partition, otherwise assume they're what they need to be...
  if [ "$ckern_size" =  "1" -o "$croot_size" = "1" ]
  then
    while :
    do
      read -p "Enter the size in gigabytes you want to reserve for ElementaryOS. Acceptable range is 5 to $max_ubuntu_size  but $rec_ubuntu_size is the recommended maximum: " ubuntu_size
      if [ ! $ubuntu_size -ne 0 2>/dev/null ]
      then
        echo -e "\n\nNumbers only please...\n\n"
        continue
      fi
      if [ $ubuntu_size -lt 5 -o $ubuntu_size -gt $max_ubuntu_size ]
      then
        echo -e "\n\nThat number is out of range. Enter a number 5 through $max_ubuntu_size\n\n"
        continue
      fi
      break
    done
    # We've got our size in GB for ROOT-C so do the math...

    #calculate sector size for rootc
    rootc_size=$(($ubuntu_size*1024*1024*2))

    #kernc is always 16mb
    kernc_size=32768

    #new stateful size with rootc and kernc subtracted from original
    stateful_size=$(($state_size - $rootc_size - $kernc_size))

    #start stateful at the same spot it currently starts at
    stateful_start="`cgpt show -i 1 -n -b -q ${target_disk}`"

    #start kernc at stateful start plus stateful size
    kernc_start=$(($stateful_start + $stateful_size))

    #start rootc at kernc start plus kernc size
    rootc_start=$(($kernc_start + $kernc_size))

    #Do the real work

    echo -e "\n\nModifying partition table to make room for ElementaryOS."
    echo -e "Your Chromebook will reboot, wipe your data and then"
    echo -e "you should re-run this script..."
    umount -f /mnt/stateful_partition

    # stateful first
    cgpt add -i 1 -b $stateful_start -s $stateful_size -l STATE ${target_disk}

    # now kernc
    cgpt add -i 6 -b $kernc_start -s $kernc_size -l KERN-C ${target_disk}

    # finally rootc
    cgpt add -i 7 -b $rootc_start -s $rootc_size -l ROOT-C ${target_disk}

    reboot
    exit
  fi
fi

# hwid lets us know if this is a Mario (Cr-48), Alex (Samsung Series 5), ZGB (Acer), etc
hwid="`crossystem hwid`"

chromebook_arch="`uname -m`"

eos_version=${1:-luna}
ubuntu_metapackage="elementary-desktop"
ubuntu_version="12.04"

if [ "$eos_version" = "dev" ]
then
  eos_version="freya"
  ubuntu_version="14.04"
elif [ "$eos_version" = "freya" ]
then
  ubuntu_version="14.04"
fi

if [ "$chromebook_arch" = "x86_64" ]
then
  ubuntu_arch="amd64"
elif [ "$chromebook_arch" = "i686" ]
then
  ubuntu_arch="i386"
elif [ "$chromebook_arch" = "armv7l" ]
then
  ubuntu_arch="armhf"
else
  echo -e "Error: This script doesn't know how to install ChrUbuntu on $chromebook_arch"
  exit
fi

echo -e "\nChrome device model is: $hwid\n"

echo -e "Installing Ubuntu ${ubuntu_version} with ElementaryOS ${eos_version} patches"

echo -e "Kernel Arch is: $chromebook_arch  Installing Ubuntu Arch: $ubuntu_arch\n"

read -p "Press [Enter] to continue..."

if [ "$eos_version" = "freya" ]
then
  echo -e "WARNING: You are installing eOS freya, which is currently in Beta.\nIt is broken, and it won't work properly!\nLast chance to hit Ctrl-C!\n"
  read -p "Press [Enter] to continue..."
fi

if [ ! -d /mnt/stateful_partition/ubuntu ]
then
  mkdir /mnt/stateful_partition/ubuntu
fi

cd /mnt/stateful_partition/ubuntu

if [[ "${target_disk}" =~ "mmcblk" ]]
then
  target_rootfs="${target_disk}p7"
  target_kern="${target_disk}p6"
else
  target_rootfs="${target_disk}7"
  target_kern="${target_disk}6"
fi

echo "Target Kernel Partition: $target_kern  Target Root FS: ${target_rootfs}"

if mount|grep ${target_rootfs}
then
  echo "Refusing to continue since ${target_rootfs} is formatted and mounted. Try rebooting"
  exit
fi

mkfs.ext4 ${target_rootfs}

if [ ! -d /tmp/urfs ]
then
  mkdir /tmp/urfs
fi
mount -t ext4 ${target_rootfs} /tmp/urfs

ubuntu_version_file="$ubuntu_version"
if [ "$ubuntu_version" = "12.04" ]
then
  ubuntu_version_file="12.04.4"
fi
tar_file="http://cdimage.ubuntu.com/ubuntu-core/releases/$ubuntu_version/release/ubuntu-core-$ubuntu_version_file-core-$ubuntu_arch.tar.gz"
wget -O - $tar_file | tar xzvvp -C /tmp/urfs/

mount -o bind /proc /tmp/urfs/proc
mount -o bind /dev /tmp/urfs/dev
mount -o bind /dev/pts /tmp/urfs/dev/pts
mount -o bind /sys /tmp/urfs/sys

if [ -f /usr/bin/old_bins/cgpt ]
then
  cp /usr/bin/old_bins/cgpt /tmp/urfs/usr/bin/
else
  cp /usr/bin/cgpt /tmp/urfs/usr/bin/
fi

chmod a+rx /tmp/urfs/usr/bin/cgpt
cp /etc/resolv.conf /tmp/urfs/etc/
echo chrubuntu > /tmp/urfs/etc/hostname
#echo -e "127.0.0.1       localhost
echo -e "\n127.0.1.1       chrubuntu" >> /tmp/urfs/etc/hosts
# The following lines are desirable for IPv6 capable hosts
#::1     localhost ip6-localhost ip6-loopback
#fe00::0 ip6-localnet
#ff00::0 ip6-mcastprefix
#ff02::1 ip6-allnodes
#ff02::2 ip6-allrouters" > /tmp/urfs/etc/hosts

cr_install="wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
echo \"deb http://dl.google.com/linux/chrome/deb/ stable main\" >> /etc/apt/sources.list.d/google-chrome.list
apt-get update
apt-get -y install google-chrome-stable"
if [ $ubuntu_arch = 'armhf' ]
then
  cr_install='apt-get -y install chromium-browser'
fi

add_apt_repository_package='software-properties-common'
ubuntu_major_version=${ubuntu_version:0:2}
ubuntu_minor_version=${ubuntu_version:3:2}
if [ $ubuntu_major_version -le 12 ] && [ $ubuntu_minor_version -lt 10 ]
then
  add_apt_repository_package='python-software-properties'
fi

echo -e "apt-get -y update
apt-get -y dist-upgrade
apt-get -y install ubuntu-minimal wget $add_apt_repository_package
if [ \"$eos_version\" = \"freya\" ]
then
  add-apt-repository -y \"deb http://archive.ubuntu.com/ubuntu trusty universe\"
  add-apt-repository -y \"deb http://archive.ubuntu.com/ubuntu trusty multiverse\"
  add-apt-repository -y ppa:elementary-os/daily
else
  add-apt-repository -y \"deb http://archive.ubuntu.com/ubuntu precise universe\"
  add-apt-repository -y \"deb http://archive.ubuntu.com/ubuntu precise multiverse\"
  add-apt-repository -y ppa:elementary-os/os-patches
  add-apt-repository -y ppa:elementary-os/stable
  apt-add-repository -y ppa:versable/elementary-update

  elementary_tweaks="elementary-tweaks"
fi
apt-get update
apt-get -y install nano whois gedit traceroute switchboard-gnome-control-center pantheon-files screen $elementary_tweaks $ubuntu_metapackage
$cr_install
if [ -f /usr/lib/lightdm/lightdm-set-defaults ]
then
  /usr/lib/lightdm/lightdm-set-defaults --autologin user
fi
useradd -m user -s /bin/bash
echo user | echo user:user | chpasswd
adduser user adm
adduser user sudo" > /tmp/urfs/install-ubuntu.sh

chmod a+x /tmp/urfs/install-ubuntu.sh
chroot /tmp/urfs /bin/bash -c /install-ubuntu.sh
rm /tmp/urfs/install-ubuntu.sh

KERN_VER=`uname -r`
mkdir -p /tmp/urfs/lib/modules/$KERN_VER/
cp -ar /lib/modules/$KERN_VER/* /tmp/urfs/lib/modules/$KERN_VER/
if [ ! -d /tmp/urfs/lib/firmware/ ]
then
  mkdir /tmp/urfs/lib/firmware/
fi
cp -ar /lib/firmware/* /tmp/urfs/lib/firmware/

echo "console=tty1 debug verbose root=${target_rootfs} rootwait rw lsm.module_locking=0" > kernel-config
vbutil_arch="x86"
if [ $ubuntu_arch = "armhf" ]
then
  vbutil_arch="arm"
fi

current_rootfs="`rootdev -s`"
current_kernfs_num=$((${current_rootfs: -1:1}-1))
current_kernfs=${current_rootfs: 0:-1}$current_kernfs_num

vbutil_kernel --repack ${target_kern} \
    --oldblob $current_kernfs \
    --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
    --version 1 \
    --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
    --config kernel-config \
    --arch $vbutil_arch

#Set Ubuntu kernel partition as top priority for next boot (and next boot only)
cgpt add -i 6 -P 5 -T 1 ${target_disk}

echo -e "

Installation seems to be complete. If ElementaryOS fails when you reboot,
power off your Chrome OS device and then turn it back on. You'll be back
in Chrome OS. If you're happy with ElementaryOS when you reboot be sure to run:

sudo cgpt add -i 6 -P 5 -S 1 ${target_disk}

To make it the default boot option. The login is:

Username:  user
Password:  user

We're now ready to start ElementaryOS!
"

read -p "Press [Enter] to reboot..."

reboot
