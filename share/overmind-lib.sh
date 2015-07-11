#!/bin/sh
# Copyright 2015
# License: BSD
# Kris Moore <kris@pcbsd.org>

locate_pool()
{
  pools="$(zpool list -H -o name)"

  for i in $pools ; do
     zfs list -H $i/overmind >/dev/null 2>/dev/null
     if [ $? -eq 0 ] ; then
       pool="$i"
       return 0
     fi
  done
  return 1
}

# Start the inital overmind setup 
do_init()
{
  echo "This appears to be your first time running overmind, please take a"
  echo "moment to do the following setup."

  # Prompt for which zpool
  # Create $pool/overmind

  # Ask which device for PXE

  # Ask if enabling NIS

  # Ask if client can associate
}
