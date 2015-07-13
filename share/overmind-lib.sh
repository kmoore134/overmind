#!/bin/sh
# Copyright 2015
# License: BSD
# Kris Moore <kris@pcbsd.org>

# Default dataset
DSET="/overmind"

# The default node dataset
DNODE="${DSET}/default-node"

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

  sed -i '' "s|%%PXEROOT%%|${DNODE}|g" ${PREFIX}/etc/dhcpd.conf
  sed -i '' "s|%%GRUBPXE%%|${DNODE}/boot/grub.pxe|g" ${PREFIX}/etc/dhcpd.conf
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

  # Create the grub PXE file
  grub-mkstandalone -O i386-pc-pxe -o ${DNODE}/boot/grub.pxe ${DNODE}/boot/grub/grub.cfg
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

  # Create $pool/overmind
  echo "Creating ${newpool}${DSET}"
  rc_halt "zfs create ${newpool}${DSET}"
  if [ ! -d "/overmind" ] ; then
    rc_halt "mkdir /overmind"
  fi
  POOL="${newpool}"

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
 
  # Set the default NIC
  set_prop "${POOL}${DSET}" "pxenic" "${newnic}"

  # Ask if enabling NIS
  echo "Do you plan on using NIS for user authentication of nodes?"
  echo -e "(Y/N):\c"
  read newnis
 
  case ${newnis} in
     Y|y|yes) echo "Enabling NIS" 
	      enable_nis
              ;;
    N|n|no|*) echo "Disabling NIS" 
	      disable_nis
              ;;
  esac

  # Ask if client can associate
  echo "Allow clients to self-associate with nodes?"
  echo -e "(Y/N):\c"
  read newasso
 
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
