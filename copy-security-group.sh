#!/bin/bash

# Function to display help message
display_help() {
    echo "Usage: $0 --group-mapping=neutron_id1=sprut_id1,neutron_id2=sprut_id2,... --groups=group_name1,group_name2,..."
    echo
    echo "Options:"
    echo "  --group-mapping    Specifies the mapping of Neutron security group IDs to Sprut security group IDs."
    echo "  --groups           Specifies the names of security groups to be copied from Neutron to Sprut."
    echo
    echo "Example:"
    echo "  $0 --group-mapping=e70baf6b=5a60883e-c165-4f2d-9477-4c417acd5d6f,4b345b50-df8b-4e21-8fd5-29c90c6d4918=8492ee54-a0a6-4dd1-a8af-0c73d4b5edf5 --groups=test-neutron-sg"
    echo
    echo "This script copies security group rules from the source Neutron environment to the target Sprut environment."
}

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed."
    echo "jq is a lightweight and flexible command-line JSON processor."
    echo "You can install jq using the following commands:"
    echo "For Ubuntu/Debian:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y jq"
    echo "For CentOS/RHEL:"
    echo "  sudo yum install -y epel-release"
    echo "  sudo yum install -y jq"
    echo "For macOS using Homebrew:"
    echo "  brew install jq"
    exit 1
fi

# Function to get the authentication token
get_auth_token() {
    local token=$(openstack token issue -c id -f value)
    echo "$token"
}

# Function to check if a security group exists and get its ID
get_sg_id() {
    local sg_name="$1"
    local sg_id=$(openstack security group show "$sg_name" -f value -c id 2>/dev/null)
    echo "$sg_id"
}

# Function to create security group with '-sprut' postfix
create_sg() {
    local sg_name="$1"
    local new_sg_name="${sg_name}-sprut"
    local token="$2"

    local url="https://infra.mail.ru:9696/infra/network/v2.0/security-groups"

    local data=$(cat <<EOF
{
    "backend" : "sprut",
    "security_group": {
        "name": "$new_sg_name",
        "description": "Copy of $sg_name"
    }
}
EOF
    )

    curl -s -X POST $url \
        -H "Content-Type: application/json" \
        -H "X-Auth-Token: $token" \
        -H "X-SDN: SPRUT" \
        -d "$data"
}

# Function to remove the default egress rule
remove_default_egress_rule() {
    local sg_id="$1"

    # Get the rule ID of the default egress rule
    local rule_ids=$(openstack security group rule list "$sg_id" -f json | jq -r '.[] | select(.Direction == "egress" and ."IP Range" == "0.0.0.0/0" and ."Port Range" == "") | .ID')

    # Remove the default egress rule
    for id in $rule_ids; do
        openstack security group rule delete "$id"
    done
}

# Function to copy security group rules from one group to another
copy_sg_rules() {
    local src_sg="$1"
    local dest_sg="$2"
    local -n mapping=$3

    # Get the rule IDs of the source security group
    local rules_json=$(openstack security group show "$src_sg" -f json | jq '.rules')

    # Iterate over each rule to fetch full details
    for rule in $(echo "${rules_json}" | jq -r '.[] | @base64'); do
        _jq() {
            echo "${rule}" | base64 --decode | jq -r "${1}"
        }

        local direction=$(_jq '.direction')
        local protocol=$(_jq '.protocol')
        local port_range_min=$(_jq '.port_range_min')
        local port_range_max=$(_jq '.port_range_max')
        local ip_range=$(_jq '.remote_ip_prefix')
        local ethertype=$(_jq '.ethertype')
        local description=$(_jq '.description')
        local remote_sg=$(_jq '.remote_group_id')

        # Check for specific group names and get corresponding IDs
        if [[ "$remote_sg" != "null" ]]; then
            local old_remote_sg="$remote_sg"
            remote_sg=$(echo ${mapping[$remote_sg]})
            echo "Replacing Neutron SecurityGroup ID '$old_remote_sg' with Sprut SecurityGroup ID '$remote_sg'"
        fi

        # Construct command for creating rule
        local cmd="openstack security group rule create $dest_sg"
        [ "$protocol" != "null" ] && cmd+=" --protocol $protocol"
        [ "$port_range_min" != "null" ] && cmd+=" --dst-port $port_range_min:$port_range_max"
        [ "$ip_range" != "null" ] && [ "$remote_sg" == "null" ] && cmd+=" --remote-ip $ip_range"
        [ "$direction" == "egress" ] && cmd+=" --egress"
        [ "$direction" == "ingress" ] && cmd+=" --ingress"
        [ "$ethertype" != "null" ] && cmd+=" --ethertype $ethertype"
        [ "$description" != "null" ] && cmd+=" --description \"$description\""
        [ "$remote_sg" != "null" ] && cmd+=" --remote-group $remote_sg"

        # Execute the command
        echo "Executing: $cmd"
        if $cmd; then
            echo "Rule created successfully for $dest_sg"
        else
            echo "Failed to create rule for $dest_sg"
        fi
    done
}

# Get the authentication token
echo "Getting auth token"
token=$(get_auth_token)

# Initialize statistics
declare -A stats
stats[success]=0
stats[fail]=0

# Read command-line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --group-mapping=*)
            group_mapping="${1#*=}"
            ;;
        --groups=*)
            groups="${1#*=}"
            ;;
        --help)
            display_help
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            display_help
            exit 1
            ;;
    esac
    shift
done

# Check if group mapping is provided
if [ -z "$group_mapping" ]; then
    echo "No group-mapping provided."
fi

# Parse group mapping
declare -A sg_mapping
if [ -n "$group_mapping" ]; then
    IFS=',' read -r -a mappings <<< "$group_mapping"
    for mapping in "${mappings[@]}"; do
        IFS='=' read -r neutron_id sprut_id <<< "$mapping"
        sg_mapping["$neutron_id"]="$sprut_id"
    done
fi

# Read each security group name from the command line arguments
IFS=',' read -r -a sg_names <<< "$groups"

for sg_name in "${sg_names[@]}"; do
    # Trim whitespace
    sg_name=$(echo "$sg_name" | xargs)

    echo "------------------------------------"
    echo "Checking if group '$sg_name' exists..."
    
    # Check if the security group exists
    sg_id=$(get_sg_id "$sg_name")
    if [ -z "$sg_id" ]; then
        echo "No SecurityGroup found for '$sg_name'"
        stats[fail]=$((stats[fail]+1))
        continue
    fi

    new_sg_name="${sg_name}-sprut"
    echo "Checking if group '$new_sg_name' already exists..."
    
    # Check if the target security group with postfix exists
    new_sg_id=$(get_sg_id "$new_sg_name")
    if [ ! -z "$new_sg_id" ]; then
        echo "SecurityGroup '$new_sg_name' already exists"
        stats[fail]=$((stats[fail]+1))
        continue
    fi

    echo "Creating new security group '$new_sg_name'..."
    create_sg "$sg_name" "$token"
    
    echo "Removing default egress rule from '$new_sg_name'..."
    remove_default_egress_rule "$new_sg_name"

    echo "Copying rules from '$sg_name' to '$new_sg_name'..."
    copy_sg_rules "$sg_id" "$new_sg_name" sg_mapping

    echo "Copying finished for '$sg_name'"
    stats[success]=$((stats[success]+1))
done

echo "------------------------------------"
echo "Processing complete."
echo "Statistics:"
echo "Successfully copied: ${stats[success]}"
echo "Failed to copy: ${stats[fail]}"
