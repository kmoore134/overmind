#!/bin/sh

PREFIX="/usr/local"

# Source our functions
. ${PREFIX}/share/overmind/overmind-lib.sh

usage()
{
  cat << EOF

EOF
}

locate_pool
if [ $? -ne 0 ] ; then
  if [ ${1} = "init" ] ; then
    do_init
    exit $?
  fi
  echo "overmind has not yet been setup. Please run 'overmind init'"
  exit 0
fi

case $1 in
   restart_dhcpd) enable_dhcpd ;;
   *) usage ;;
esac
