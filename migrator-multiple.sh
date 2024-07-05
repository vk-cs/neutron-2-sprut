#!/bin/bash

echo "
#######################################
#                                     #
#        Port Migration Script        #
#                                     #
#######################################

Mandatory Input Data:

Input file format:
server_name1,dest_net1,dest_subnet1,floating_ip_id1
server_name2,dest_net2,dest_subnet2,floating_ip_id2

Note: If floating_ip_id is not provided, the script will not attach a Floating IP.

Optional:
--all-secgroup-sprut-id=<id>
--ssh-www-secgroup-sprut-id=<id>

"

# Parse arguments
for i in "$@"
do
case $i in
    --all-secgroup-sprut-id=*)
    all_sg_sprut_id="${i#*=}"
    shift
    ;;
    --ssh-www-secgroup-sprut-id=*)
    ssh_www_sg_sprut_id="${i#*=}"
    shift
    ;;
    *)
    # unknown option
    ;;
esac
done

# Function Definitions

# Capture port information with full details
function capture_info_full {
    echo "Executing step 1: Capturing port information"
    
    # Define the migrated port name format
    migrated_port_name="${sname}_migrated_port"
    
    # Check if the migrated port already exists and is attached to the server
    existing_migrated_port_info=$(openstack port list -f value -c ID -c Name | grep "$migrated_port_name")
    existing_migrated_port_id=$(echo "$existing_migrated_port_info" | awk '{print $1}' | head -n 1)
    
    if [ ! -z "$existing_migrated_port_id" ]; then
        # Check if this port is already attached to the server
        echo "Migrated port ${migrated_port_name} exists, checking for attachment..."
        attached_port_info=$(openstack server port list $sname -f value -c ID | grep "$existing_migrated_port_id")
        if [ ! -z "$attached_port_info" ]; then
            echo "Migrated port $migrated_port_name already exists and is attached to server $sname. Skipping..."
            echo "********************************************"
            return 1 # Use return code 1 to indicate skipping
        fi
    fi
    
    # Proceed with capturing port information if no migrated port is attached
    port_output=$(openstack port list --server $sname -c id -c "MAC Address" -c "Fixed IP Addresses")
    srcpid=$(echo "$port_output" | awk -F'|' 'NR==4{print $2}' | sed 's/ //g')
    mcs=$(echo "$port_output" | awk -F'|' 'NR==4{print $3}' | sed 's/ //g')
    ips=$(echo "$port_output" | awk -F'|' 'NR==4{print $4}' | grep -oP "ip_address='\K[^']+")
    
    echo "Source Port ID is:        $srcpid"
    echo "Source Port IP Addr is:   $ips"
    echo "Source Port MAC Addr is:  $mcs"
    echo "********************************************"
}

# Capture server ID and security group names
function capture_id_and_sec_group {
    echo "Executing step 2: Capturing server ID and security group names"
    
    server_output=$(openstack server show $sname)
    servid=$(echo "$server_output" | awk -F'|' '/\| id / {print $3}' | sed 's/ //g')
    echo "Server ID is:             $servid"

    # Fetch security group IDs
    sec_group_ids=$(openstack port show $srcpid -c security_group_ids -f value)

    # Preprocess to remove brackets and split by comma
    sec_group_ids=$(echo $sec_group_ids | tr -d '[]' | tr -d '"' | tr -d "'")

    # Convert to array and iterate
    IFS=',' read -ra ADDR <<< "$sec_group_ids"
    sec_group_names=()
    for sec_group_id in "${ADDR[@]}"; do
        sec_group_name=$(openstack security group show $sec_group_id -c name -f value)
        sec_group_names+=("$sec_group_name")
    done
    echo "Security Groups captured: ${sec_group_names[@]}"
    echo "********************************************"
}

# Create port in target network with source IP and MAC, with checks for existing port by name using grep
function create_port_with_mac_ip {
    echo "Executing step 3: Creating port with source IP and MAC"
    
    # Define the port name format
    port_name="${sname}_migrated_port"
    
    # Attempt to find an existing port by name using grep
    existing_port_info=$(openstack port list -f value -c ID -c Name | grep "$port_name")
    existing_port_id=$(echo "$existing_port_info" | awk '{print $1}' | head -n 1)
    
    if [ ! -z "$existing_port_id" ]; then
        echo "Port named $port_name already exists. Port ID: $existing_port_id"
        pmigid=$existing_port_id
    else
        # If no existing port found, attempt to create a new port
        create_port_cmd="openstack port create --network $defnet --fixed-ip subnet=$defsubnet,ip-address=$ips --mac-address=$mcs $port_name"
        echo "Running command: $create_port_cmd"
        new_port_output=$($create_port_cmd)
        pmigid=$(echo "$new_port_output" | awk -F'|' '/\| id / {print $3}' | sed 's/ //g')
        echo "Step 3 complete (New Port Created)"
    fi
    echo "********************************************"
}

# Disconnect existing port from server
function detach_source_port {
    echo "Executing step 4: Disconnecting existing port from server"
    
    detach_port_cmd="openstack server remove port $servid $srcpid"
    echo "Running command: $detach_port_cmd"
    $detach_port_cmd
    echo "Step 4 complete (Source port disconnected from server $sname)"
    echo "********************************************"
}

# Connect new port to server
function attach_new_port {
    echo "Executing step 5: Connecting new port to server"
    
    attach_port_cmd="openstack server add port $servid $pmigid"
    echo "Running command: $attach_port_cmd"
    $attach_port_cmd
    echo "Step 5 complete (New port attached to server)"
    echo "********************************************"
}

# Set security groups on the new port
function set_security_groups {
    echo "Executing step 6: Setting security groups on new port"
    echo "Setting captured groups: ${sec_group_names[@]}"
    
    for sec_group_name in "${sec_group_names[@]}"; do
        echo "Original Security Group: $sec_group_name"
        if [[ "$sec_group_name" == "all" ]]; then
            modified_sec_group_id="$all_sg_sprut_id"
        elif [[ "$sec_group_name" == "default" ]]; then
            modified_sec_group_name="default-sprut"
            if openstack security group show "$modified_sec_group_name" -c id -f value &> /dev/null; then
                modified_sec_group_id=$(openstack security group show "$modified_sec_group_name" -c id -f value)
            else
                echo "Security Group $modified_sec_group_name does not exist, skipping..."
                continue
            fi
        elif [[ "$sec_group_name" == "ssh+www" ]]; then
            modified_sec_group_id="$ssh_www_sg_sprut_id"
        else
            modified_sec_group_name="${sec_group_name}-sprut"
            # Check if modified security group exists before setting it
            if openstack security group show "$modified_sec_group_name" -c id -f value &> /dev/null; then
                modified_sec_group_id=$(openstack security group show "$modified_sec_group_name" -c id -f value)
            else
                echo "Security Group $modified_sec_group_name does not exist, skipping..."
                continue
            fi
        fi
        echo "Modified Security Group ID: $modified_sec_group_id"
        set_sg_cmd="openstack port set --security-group $modified_sec_group_id $pmigid"
        echo "Running command: $set_sg_cmd"
        $set_sg_cmd
        echo "Security Group $sec_group_name set on new port"
    done
    echo "Step 6 complete (Security groups assignment complete)"
    echo "********************************************"
}

# Attach Floating IP to the new port if provided
function attach_floating_ip {
    if [ ! -z "$floating_ip_id" ]; then
        echo "Executing step 7: Attaching Floating IP"
        
        attach_fip_cmd="openstack floating ip set --port $pmigid $floating_ip_id"
        echo "Running command: $attach_fip_cmd"
        $attach_fip_cmd
        echo "Floating IP $floating_ip_id attached to new port"
        echo "********************************************"
    fi
}

# Process migration for each server
function process_migration {
    sname=$1
    defnet=$2
    defsubnet=$3
    floating_ip_id=$4

    echo "Processing migration for server: $sname"
    capture_info_full
    if [ $? -eq 1 ]; then
        # Skipping logic, e.g., continue in a loop
        continue
    fi
    capture_id_and_sec_group
    create_port_with_mac_ip
    detach_source_port
    attach_new_port
    set_security_groups
    attach_floating_ip
    echo "Migration completed for server: $sname"
    echo "---------------------------------------"
}

# Main script execution

if [ -z "$1" ]; then
    echo "Error: No input file provided."
    exit 1
fi

start_time=$(date +%s)

while IFS=, read -r server_name dest_net dest_subnet floating_ip_id
do
    process_migration "$server_name" "$dest_net" "$dest_subnet" "$floating_ip_id"
done < "$1"

end_time=$(date +%s)
elapsed_time=$(($end_time - $start_time))
echo "Elapsed time: $elapsed_time seconds"
