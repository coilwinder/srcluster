#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

function bail_out {
  echo -e "\033[0;31m"

  if [[ -n "${1}" ]]; then
  	echo "${1}"
  	echo -e "\033[0m"
  fi
  
  echo -e "Usage: $0 <inventory_directory> [present|deleted]\n"
  echo -e "\tinventory_directory: the directory containing the inventory goal (compulsory)"
  echo -e "\tpresent: the droplet will be created if it doesn't exist (default)"
  echo -e "\tdeleted: the droplet will be destroyed if it exists\n"

  exit 1
}

# Try to remove created resources if got error
function delete_created() {
  for host in ${CREATED_HOSTS:-}; do
    echo "Deleting ${host}"          
    
    ansible_command="ansible localhost -c local -i ${TEMP_INVENTORY} -m digital_ocean"
    ansible_command+=" -a \"state=deleted command=droplet private_networking=yes unique_name=yes" 
    ansible_command+=" name=${host} size_id=${SIZE:-512mb} image_id=${IMAGE:-ubuntu-16-04-x64}"
    ansible_command+=" region_id=${REGION:-fra1}\""

    eval ${ansible_command} &>/dev/null
  done

  exit 1
}

# if got error then remove created resources
trap "delete_created" ERR SIGINT SIGTERM

# Default droplet parameters
DEFAULT_SIZE="4gb"   			# 512mb (override with do_size_slug)
DEFAULT_REGION="fra1" 			# ams2 (override with do_region_slug)
DEFAULT_IMAGE="ubuntu-16-04-x64" 	# Ubuntu 16.04 x64 (override with do_image_slug)
DEFAULT_KEY="13271967"    		# SSH key numeric identifier

# Entry for temporary inventory
# This is a temp inventory generated to start the DO droplets
LOCALHOST_ENTRY="localhost ansible_python_interpreter=/usr/bin/python2"

# Path to inventory directory
INVENTORY="${1:-}"

# Remove trailing slash
INVENTORY="${INVENTORY%/}"

# Set state default value to present
STATE=${2:-"present"}

# Check script parameters
[[ -d "${INVENTORY}" ]] \
  || bail_out "<inventory_directory> does not exist, is not a directory, or is not set"


[[ "${STATE}" == "present" || "${STATE}" == "deleted" ]] \
  || bail_out "second parameter must be [present|deleted]"

# Check for JSON processor
which jq &>/dev/null || bail_out "Unable to find required binary 'jq'."

# digital_ocean module command to use
# name, size, region, image and key will be filled automatically
COMMAND="state=${STATE} command=droplet private_networking=yes unique_name=yes"

# Get a list of hosts from inventory dir
HOSTS=$(ansible -i $1 --list-hosts all \
          | awk '{ print $1 }' | awk '{if (NR!=1) {print}}' | tr '\n' ' ')

# Clean up previously generated inventory
rm -f ${INVENTORY}/generated

# Creating temporary inventory with only localhost in it
TEMP_INVENTORY=$(mktemp)
echo "Creating temporary inventory in ${TEMP_INVENTORY}"
echo "${LOCALHOST_ENTRY}" >"${TEMP_INVENTORY}"

for host in ${HOSTS}; do
  
  # Check parameters in inventory file
  set +o pipefail

  SIZE=$(grep "${host}" "${INVENTORY}/hosts" | grep do_size_slug | sed -e 's/.*do_size_slug=\(\d*\)/\1/')

  REGION=$(grep "${host}" "${INVENTORY}/hosts" | grep do_region_slug | sed -e 's/.*do_region_slug=\(\d*\)/\1/')

  IMAGE=$(grep "${host}" "${INVENTORY}/hosts" | grep do_image_slug | sed -e 's/.*do_image_slug=\(\d*\)/\1/')

  KEY=$(grep "${host}" "${INVENTORY}/hosts" | grep do_key | sed -e 's/.*do_key=\(\d*\)/\1/') 

  set -o pipefail

  SIZE="${SIZE:-$DEFAULT_SIZE}"
  REGION="${REGION:-$DEFAULT_REGION}"
  IMAGE="${IMAGE:-$DEFAULT_IMAGE}"
  KEY="${KEY:-$DEFAULT_KEY}"
 
  if [[ "${STATE}" == "present" ]]; then
    echo "Creating ${host} of size ${SIZE} using image ${IMAGE} in region ${REGION} with key ${KEY}"
  else
    echo "Deleting ${host}"
  fi

  CREATED_HOSTS="${CREATED_HOSTS:-} ${host}"

  CHANGED=$(ansible localhost -c local -i "${TEMP_INVENTORY}" -m digital_ocean \
    -a "${COMMAND} name=${host} size_id=${SIZE} image_id=${IMAGE} region_id=${REGION} ssh_key_ids=${KEY}" \
      | sed -e 's/localhost | SUCCESS => //' \
      | jq '.changed')      

  if [[ "${CHANGED}" == "false" ]]; then
    CREATED_HOSTS="${CREATED_HOSTS/$host/}"
  fi

done

# Now do it again to fill up complementary inventory
if [[ "${STATE}" == "present" ]]; then
  for host in ${HOSTS}; do
    echo "Checking droplet ${host}"
    
    set +o pipefail
    
    IP=$(ansible localhost -c local -i ${TEMP_INVENTORY} -m digital_ocean \
      -a "state=present command=droplet unique_name=yes name=${host}" \
        | sed -e 's/localhost | SUCCESS => //' \
        | jq '.droplet.networks.v4[] | select(.type == "public") | .ip_address' \
        | cut -f2 -d'"')

    set -o pipefail

    echo "ansible_ssh_host: ${IP}" >"${INVENTORY}/host_vars/${host}"
  done
fi

echo "All done !"

