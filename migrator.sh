#!/bin/bash

# Banner

echo "

#######################################
#                                     #
#        Port Migration Script        #
#                                     #
#######################################

Mandatory Input Data:

--opt key should followed by either clone or noclone value

clone:   will copy source IP and MAC addresses
noclone: will create a new port in target network / subnet with random IP and MAC addresses

1. Server Name
2. Destination Network in Sprut SDN
3. Destination Subnet in Sprut SDN

"

# User Input
function init {
    read -p "Enter Server Name: " sname
    read -p "Enter Sprut Network Name: " defnet
    read -p "Enter Sprut Subnet Name: " defsubnet

    echo "
    Port information will be captured from $sname server"

    echo "
    New port will be created in $defnet network in $defsubnet subnet"
}

# Step 1.1 opt 1. Port Specifications
function capture_info_full {
    port_output=$(openstack port list --server $sname -c id -c "MAC Address" -c "Fixed IP Addresses")
    srcpid=$(echo "$port_output" | awk -F'|' 'NR==4{print $2}' | sed 's/ //g')
    mcs=$(echo "$port_output" | awk -F'|' 'NR==4{print $3}' | sed 's/ //g')
    ips=$(echo "$port_output" | awk -F'|' 'NR==4{print $4}' | grep -oP "ip_address='\K[^']+" )

    echo "
    Source Port ID is:        $srcpid"

    echo "
    Source Port IP Addr is:   $ips"

    echo "
    Source Port MAC Addr is:  $mcs"
}

# Step 1.1 opt 2. Port Specifications
function capture_info_short {
    port_output=$(openstack port list --server $sname -c id -c "MAC Address" -c "Fixed IP Addresses")
    srcpid=$(echo "$port_output" | awk -F'|' 'NR==4{print $2}' | sed 's/ //g')

    echo "
    Source Port ID is:        $srcpid"
}

# Step 1.2 Server ID
function capture_id {
    server_output=$(openstack server show $sname)
    servid=$(echo "$server_output" | awk -F'|' '/\| id / {print $3}' | sed 's/ //g')

    echo "
    Server ID is:             $servid"

    echo "
    Step 1 complete (Source Port Data Captured)"
}

# Step 2 opt 1. Create Port in Sprut with source IP and MAC.
function sprut_port_mac_ip {
    new_port_output=$(openstack port create --network $defnet --fixed-ip subnet=$defsubnet,ip-address=$ips --mac-address=$mcs "${sname}_migrated_port")
    pmigid=$(echo "$new_port_output" | awk -F'|' '/\| id / {print $3}' | sed 's/ //g')

    echo "
    Step 2 complete (New Port Created)"
}

# Step 2 opt 2. Create Port in Sprut witout source IP and MAC.
function sprut_port_nomac_noip {
    new_port_output=$(openstack port create --network $defnet --fixed-ip subnet=$defsubnet "${sname}_migrated_port")
    pmigid=$(echo "$new_port_output" | awk -F'|' '/\| id / {print $3}' | sed 's/ //g')

    echo "
    Step 2 complete (New Port Created)"
}

# Step 3. Disconnect Existing Port From Server
function neutron_port_detach {
    openstack server remove port $servid $srcpid

    echo "
    Step 3 complete (Source port disconnected From server $sname)"
}

# Step 4. Connect New Port To Server
function sprut_port_attach {
    openstack server add port $servid $pmigid

    echo "
    The Port has been moved to Sprut SDN"
}

# Execute Flow
if [ "$1" != "--opt" ] || [ -z "$2" ]; then
    echo "Error: --opt argument is mandatory and must be followed by a value <noclone> or <clone>."
    exit 1
else
    if [ "$2" == "noclone" ]; then
        init
        capture_info_short
        capture_id
        sprut_port_nomac_noip
        neutron_port_detach
        sprut_port_attach
    elif [ "$2" == "clone" ]; then
        init
        capture_info_full
        capture_id
        sprut_port_mac_ip
        neutron_port_detach
        sprut_port_attach
    else
        echo "Error: unknown option has been provided."
        exit 1	
    fi
fi
