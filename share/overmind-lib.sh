#!/bin/sh
# Copyright 2015
# License: BSD
# Kris Moore <kris@pcbsd.org>

# Default dataset
DSET="/overmind"

# The default node dataset
DNODE="${DSET}/default-node"

# Default PXE boot dir
PXEROOT="${DSET}/pxeboot"

# Exit with a error message
exit_err() {
  echo >&2 "ERROR: $*"
  exit 1
}

# Run command and halt if it fails
rc_halt()
{
  CMD="$@"

  if [ -z "${CMD}" ] ; then
    exit_err "Error: missing argument in rc_halt()"
  fi

  ${CMD}
  STATUS=$?
  if [ ${STATUS} -ne 0 ] ; then
    exit_err "Error ${STATUS}: ${CMD}"
  fi
}

set_prop()
{
  rc_halt "zfs set overmind:${2}=${3} ${1}"
}

get_prop()
{
  VAL=$(zfs get -H -o value overmind:${2} ${1} 2>/dev/null)
  export VAL
}

locate_pool()
{
  pools="$(zpool list -H -o name)"

  for i in $pools ; do
     zfs list -H $i/overmind >/dev/null 2>/dev/null
     if [ $? -eq 0 ] ; then
       export POOL="$i"
       return 0
     fi
  done
  return 1
}

# Enable NIS configuration
enable_nis()
{
  set_prop "${POOL}${DSET}" "nisserv" "YES"
}

# Disable NIS configuration
disable_nis()
{
  set_prop "${POOL}${DSET}" "nisserv" "NO"
}


# Enable self association of nodes
enable_selfasso()
{
  set_prop "${POOL}${DSET}" "nodeself" "YES"
}

# Disable self association of nodes
disable_selfasso()
{
  set_prop "${POOL}${DSET}" "nodeself" "NO"
}

enable_dhcpd()
{
  sysrc -f /etc/rc.conf dhcpd_enable="YES"
  sysrc -f /etc/rc.conf dhcpd_conf="${PREFIX}/etc/dhcpd.conf"
  get_prop "${POOL}${DSET}" "pxenic"
  sysrc -f /etc/rc.conf dhcpd_ifaces="${VAL}"
  NIC="$VAL"
  get_prop "${POOL}${DSET}" "dhcphost"
  sysrc -f /etc/rc.conf ifconfig_${NIC}="${VAL}"
  /etc/rc.d/netif start $NIC

  # Make sure tftpd is enabled
  grep -q "${PXEWORLD}" /etc/inetd.conf
  if [ $? -ne 0 ] ; then
    echo "tftp   dgram   udp     wait    root    /usr/libexec/tftpd      tftpd -l -s ${PXEWORLD}" >> /etc/inetd.conf
  fi
  sysrc -f /etc/rc.conf inetd_enable="YES"
  service inetd stop >/dev/null 2>/dev/null
  service inetd start

  # Copy over the dhcp.conf.default
  cp ${PREFIX}/share/overmind/dhcpd.conf.default ${PREFIX}/etc/dhcpd.conf

  get_prop "${POOL}${DSET}" "dhcphost"
  sed -i '' "s|%%DHCPHOST%%|${VAL}|g" ${PREFIX}/etc/dhcpd.conf
  sed -i '' "s|%%PXESERVERIP%%|${VAL}|g" ${PREFIX}/etc/dhcpd.conf
  get_prop "${POOL}${DSET}" "dhcpsubnet"
  sed -i '' "s|%%DHCPSUBNET%%|${VAL}|g" ${PREFIX}/etc/dhcpd.conf
  get_prop "${POOL}${DSET}" "dhcpnetmask"
  sed -i '' "s|%%DHCPNETMASK%%|${VAL}|g" ${PREFIX}/etc/dhcpd.conf
  get_prop "${POOL}${DSET}" "dhcpstartrange"
  sed -i '' "s|%%DHCPSTARTRANGE%%|${VAL}|g" ${PREFIX}/etc/dhcpd.conf
  get_prop "${POOL}${DSET}" "dhcpendrange"
  sed -i '' "s|%%DHCPENDRANGE%%|${VAL}|g" ${PREFIX}/etc/dhcpd.conf

  sed -i '' "s|%%PXEROOT%%|${PXEROOT}|g" ${PREFIX}/etc/dhcpd.conf
  sed -i '' "s|%%GRUBPXE%%|default-node/i386-pc/core.0|g" ${PREFIX}/etc/dhcpd.conf

  service isc-dhcpd stop >/dev/null 2>/dev/null
  service isc-dhcpd start
}

get_default_node()
{
  rc_halt "zfs create -o mountpoint=${DNODE} ${POOL}${DNODE}"
  echo "Fetching default node files..."
  # KPM - This needs to be replaced with our fancy GH distribution system eventually
  fetch -o ${DNODE}/base.txz http://download.pcbsd.org/iso/`uname -r | cut -d '-' -f 1-2`/amd64/dist/base.txz
  fetch -o ${DNODE}/kernel.txz http://download.pcbsd.org/iso/`uname -r | cut -d '-' -f 1-2`/amd64/dist/kernel.txz
  echo "Extracting default node..."
  rc_halt "tar xvpf ${DNODE}/base.txz -C ${DNODE}" 2>/dev/null
  rc_halt "tar xvpf ${DNODE}/kernel.txz -C ${DNODE}" 2>/dev/null
  rc_halt "rm ${DNODE}/base.txz"
  rc_halt "rm ${DNODE}/kernel.txz"
}

setup_default_grub()
{
  echo "Setting up grub.cfg"
  if [ ! -d "${DNODE}/boot/grub" ] ; then
    mkdir ${DNODE}/boot/grub
  fi
  rc_halt "cp ${PREFIX}/share/overmind/grub.cfg.default ${DNODE}/boot/grub/grub.cfg"

  get_prop "${POOL}${DSET}" "dhcphost"
  sed -i '' "s|%%PXESERVERIP%%|${VAL}|g" ${DNODE}/boot/grub/grub.cfg
  sed -i '' "s|%%PXEROOT%%|${DNODE}|g" ${DNODE}/boot/grub/grub.cfg

  if [ -d "${PXEROOT}/default-node" ] ; then
    rm -rf ${PXEROOT}/default-node
  fi

  # Create the grub default PXE file
  grub-mknetdir --net-directory=${PXEROOT} --subdir=default-node
  mkdir ${PXEROOT}/default-node/boot
  cp -r ${DNODE}/boot/kernel ${PXEROOT}/default-node/boot/kernel
  cp ${DNODE}/boot/grub/grub.cfg ${PXEROOT}/default-node/grub.cfg
}

# Start the inital overmind setup 
do_init()
{
  echo "This appears to be your first time running overmind, please take a"
  echo "moment to do the following setup."

  # Prompt for which zpool
  defaultpool="$(zpool list -H -o name | head -n 1)"
  echo "Which zpool do you want to create /overmind on?"
  echo -e "[${defaultpool}]:\c"
  read newpool
  if [ -z "${newpool}" ] ; then newpool="${defaultpool}" ; fi

  # Validate the pool
  zpool list -H ${newpool} >/dev/null 2>/dev/null
  if [ $? -ne 0 ] ; then
    exit_err "No such zpool: ${newpool}"
  fi

  # Ask which device for PXE
  echo "Which NIC do you want to enable DHCPD/PXE booting on?"
  echo "Available: `ifconfig -l | sed 's|lo0||g'`"
  defaultnic=$(ifconfig -l | sed 's|lo0||g' | awk '{print $1}')
  echo -e "NIC [${defaultnic}]:\c"
  read newnic
  if [ -z "${newnic}" ] ; then newnic="${defaultnic}" ; fi

  # Make sure the NIC exists
  ifconfig -l | grep -q "${newnic}"
  if [ $? -ne 0 ] ; then
    exit_err "No such NIC: ${newnic}"
  fi
 
  # Ask if enabling NIS
  echo "Do you plan on using NIS for user authentication of nodes?"
  echo -e "(Y/N):\c"
  read newnis

  # Ask if client can associate
  echo "Allow clients to self-associate with nodes?"
  echo -e "(Y/N):\c"
  read newasso

  # Confirm settings
  echo ""
  echo "Use these settings?"
  echo "ZPOOL: $newpool"
  echo "DHCP NIC: $newnic"
  echo "Client NIS: $newnis"
  echo "Client Association: $newasso"
  echo -e "(Y/N):\c"
  read tmp
  case $tmp in
    Y|y|yes) ;;
          *) exit 1 ;;
  esac
 
  # Create $pool/overmind
  echo ""
  echo "Creating ${newpool}${DSET}"
  if [ ! -d "${DSET}" ] ; then
    rc_halt "mkdir ${DSET}"
  fi
  rc_halt "zfs create -o mountpoint=${DSET} ${newpool}${DSET}"
  if [ ! -d "${PXEROOT}" ] ; then
    rc_halt "mkdir ${PXEROOT}"
  fi
  POOL="${newpool}"

  # Set the default NIC
  set_prop "${POOL}${DSET}" "pxenic" "${newnic}"

  # Set NIS settings
  case ${newnis} in
     Y|y|yes) echo "Enabling NIS" 
	      enable_nis
              ;;
    N|n|no|*) echo "Disabling NIS" 
	      disable_nis
              ;;
  esac

  # Enable association settings
  case ${newasso} in
     Y|y|yes) echo "Enabling self-association" 
	      enable_selfasso
              ;;
    N|n|no|*) echo "Disabling self-association" 
	      disable_selfasso
              ;;
  esac

  # Setup some defaults
  set_prop "${POOL}${DSET}" "dhcphost" "172.25.10.1"
  set_prop "${POOL}${DSET}" "dhcpsubnet" "172.25.10.0"
  set_prop "${POOL}${DSET}" "dhcpnetmask" "255.255.255.0"
  set_prop "${POOL}${DSET}" "dhcpstartrange" "172.25.10.50"
  set_prop "${POOL}${DSET}" "dhcpendrange" "172.25.10.250"
  set_prop "${POOL}${DSET}" "pxeroot" "${POOL}${DNODE}"

  # Fetch the default FreeBSD world / kernel for this default-node
  get_default_node

  # Setup grub.cfg
  setup_default_grub

  # Enable DHCPD
  enable_dhcpd

  echo "Initial OverMind setup complete! You may now add node images."
}
