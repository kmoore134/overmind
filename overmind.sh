#!/bin/sh

PREFIX="/usr/local"

# Source our functions
. ${PREFIX}/share/overmind/overmind-lib.sh

locate_pool
if [ $? -ne 0 ] ; then
  do_init  
fi
