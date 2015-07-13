#!/bin/sh
# Copyright 2015
# License: BSD
# Kris Moore <kris@pcbsd.org>

# Default dataset
DSET="/overmind"

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
  set_prop "${POOL}${DSET}" "NISSERV" "YES"
}

# Disable NIS configuration
disable_nis()
{
  set_prop "${POOL}${DSET}" "NISSERV" "NO"
}


# Enable self association of nodes
enable_selfasso()
{
  set_prop "${POOL}${DSET}" "NODESELF" "YES"
}

# Disable self association of nodes
disable_selfasso()
{
  set_prop "${POOL}${DSET}" "NODESELF" "NO"
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
  POOL="${newpool}"

  # Ask which device for PXE
  echo "Which NIC do you want to enable DHCPD/PXE booting on?"
  echo "Available: `ifconfig -l | sed 's|lo0||g'`"
  defaultnic=$(ifconfig -l | sed 's|lo0||g' | head -n 1)
  echo -e "NIC [${defaultnic}]:\c"
  read newnic
  if [ -z "${newnic}" ] ; then newnic="${defaultnic}" ; fi

  # Make sure the NIC exists
  ifconfig -l | grep -q "newnic"
  if [ $? -ne 0 ] ; then
    exit_err "No such NIC: ${newnic}"
  fi
 
  # Set the default NIC
  set_prop "${POOL}${DSET}" "PXENIC" "${newnic}"

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

  echo "Initial OverMind setup complete! You may now add node images."
}
