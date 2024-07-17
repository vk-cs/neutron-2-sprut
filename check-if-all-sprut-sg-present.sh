#!/bin/bash

echo "
#######################################
#                                     #
#      Security Group Check Script    #
#                                     #
#######################################

This script checks all VMs in the tenant, collects the names of the assigned security groups, and verifies if there are corresponding security groups with the '-sprut' postfix.

It will skip checking for security groups named 'default', 'ssh+www', and 'all'.

"

# Function to get a list of all VMs in the tenant
function get_all_vms {
    openstack server list -f value -c Name
}

# Function to get the security groups assigned to a VM
function get_vm_security_groups {
    local vm_name=$1
    openstack server show "$vm_name" -f json | jq -r '.security_groups[] | .name'
}

# Function to check if a security group with a given name and '-sprut' postfix exists
function check_sprut_sg_exists {
    local sg_name=$1
    openstack security group list -f value -c Name | grep -qw "${sg_name}-sprut"
}

# Main script execution
all_vms=$(get_all_vms)
sg_names=()

for vm in $all_vms; do
    echo "Checking VM: $vm"
    vm_sg_names=$(get_vm_security_groups "$vm")
    echo "Security groups found on VM $vm: $vm_sg_names"
    for sg_name in $vm_sg_names; do
        sg_names+=("$sg_name")
    done
done

# Remove duplicates and sort the list
unique_sg_names=($(echo "${sg_names[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

# Filter out the security groups that should not be checked
filtered_sg_names=()
for sg_name in "${unique_sg_names[@]}"; do
    if [[ "$sg_name" != "default" && "$sg_name" != "ssh+www" && "$sg_name" != "all" && "$sg_name" != *"-sprut" ]]; then
        filtered_sg_names+=("$sg_name")
    fi
done

# Check for corresponding '-sprut' security groups and report missing ones
missing_sg=()
for sg_name in "${filtered_sg_names[@]}"; do
    echo "Checking for corresponding '-sprut' security group for: $sg_name"
    if check_sprut_sg_exists "$sg_name"; then
        echo "Found corresponding '-sprut' group for: $sg_name"
    else
        echo "Missing corresponding '-sprut' group for: $sg_name"
        missing_sg+=("$sg_name")
    fi
done

echo "------------------------------------"
echo "Security Group Check Summary"
echo "------------------------------------"
if [ ${#missing_sg[@]} -eq 0 ]; then
    echo "All security groups have corresponding '-sprut' groups."
else
    echo "The following security groups do not have corresponding '-sprut' groups:"
    for sg in "${missing_sg[@]}"; do
        echo "- $sg"
    done
fi
echo "------------------------------------"
