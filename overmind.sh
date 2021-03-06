#!/bin/sh

PREFIX="/usr/local"

# Source our functions
. ${PREFIX}/share/overmind/overmind-lib.sh

# Export the properties passed in on the CLI
export_props () {
  for i in "$@" ; do
    if [ "$(echo $i | grep -e ".*=.*")" ] ; then
      export "om_${i}"
    fi
  done
}

usage()
{
  cat << EOF
Overmind usage
-----------------------------------------------------------------------

For more details on a command run "help <command>"

 assign - Assign a MAC address to a particular node
  clone - Clone an existing node
default - Assign a node to be the default PXE node
destroy - Destroy a node
  fetch - Fetch FreeBSD dist files and create new node
    get - Get options on nodes or server
   list - List nodes
   init - Run the first time init of the overmind server
   pull - Pull pre-built node from remote repo
    set - Set options on nodes or server
EOF
}

usage_destroy()
{

  cat << EOF
Overmind usage - destroy
-----------------------------------------------------------------------

Example:
# overmind destroy mynode

EOF

}

usage_pull()
{

}

usage_fetch()
{
  cat << EOF
Overmind usage - fetch
-----------------------------------------------------------------------

Example:
# overmind fetch node=mynode release=10.1-RELEASE

Required arguments:
  release=<release>	- The FreeBSD version to fetch

Optional args:
  arch=<arch>		- Alternative ARCH to pull, by default will use
			  the host's machine architecture
			  (Ignored if url= is used)

  ip=<address>		- Assign a static IP <address> to this node

  mac=<address>		- MAC address to assign to this node for PXE booting
			  Use the address "default" if you want un-assigned
			  PXE Clients to boot this node automatically

  node=<name>		- Nickname for the new NODE. A UUID will also be
			  assigned automatically for identification

  url=<location>	- Alternative URL to fetch dist (.txz) files from,
			  the default will pull from FreeBSD mirrors

EOF
}

parse_help()
{
  case $1 in
  fetch) usage_fetch ;;
   pull) usage_pull ;;
   list) usage_list ;;
      *) echo "Unknown command: $1"
         exit 1
         ;;
  esac
}

parse_fetch()
{
  if [ -z "$om_release" ] ; then
    exit_err "Missing release="
  fi

  fetch_freebsd_node
  exit $?
}

# Check if OverMind has been setup
locate_pool
if [ $? -ne 0 ] ; then
  if [ ${1} = "init" ] ; then
    do_init
    exit $?
  fi
  echo "overmind has not yet been setup. Please run 'overmind init'"
  exit 0
fi

# Set the variables passed in
export_props $@

case $1 in
         destroy) if [ -z "${2}" ] ; then
		    usage_destroy
		    exit 1
                  fi 
                  destroy_node "$2" ;;
           fetch) parse_fetch ;;
            help) parse_help $2 ;;
            list) list_nodes ;;
            pull) parse_pull ;;
   restart_dhcpd) enable_dhcpd ;;
               *) usage ;;
esac
