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
  do_init  
  exit $?
fi

case $1 in
   restart_dhcpd) enable_dhcpd ;;
   *) usage ;;
esac
