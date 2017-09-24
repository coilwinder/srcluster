#!/bin/bash

LOCK_FILE='/home/ansible/.sr_lock'
SSH_STR='ansible@46.101.218.33'
SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_STR}"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if $SSH_CMD "test -f ${LOCK_FILE}"
then
    echo "Error: lock file exists"
    exit 1
fi

exit 0

touch "${LOCK_FILE}"

function exit_error ()
{
   MSG="$1"
   ./provisioner.sh inventories/staging/ deleted
   echo "${MSG}"
   rm "${LOCK_FILE}"
   exit 1
}

trap "exit_error 'ERROR: exit by signal'" ERR SIGINT SIGTERM


./provisioner.sh inventories/staging/  || exit_error "ERROR on staging.provisioner step"
ansible-playbook -i inventories/staging site.yaml || exit_error "ERROR on staging.ansible step"
./provisioner.sh inventories/staging/ deleted

./provisioner.sh inventories/production || exit_error "ERROR on production.provisioner step"
ansible-playbook -i inventories/production site.yaml || exit_error "ERROR on production.ansible step"

rm "${LOCK_FILE}"



