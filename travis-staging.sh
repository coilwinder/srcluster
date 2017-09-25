#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LOCK_FILE='/home/ansible/.sr_lock'
WORK_DIR='/home/ansible/work/semrush/srwork-staging'
SSH_STR='ansible@46.101.218.33'
SSH_CMD="ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_STR}"

function exit_error() {
   MSG="$1"

   echo "${MSG}"
   $SSH_CMD "cd ${WORK_DIR} && ./provisioner.sh inventories/staging deleted"
   $SSH_CMD "rm -f ${LOCK_FILE}"

   exit 1
}

trap "exit_error 'ERROR: exit by signal'" ERR SIGINT SIGTERM

# Lock file management
if $SSH_CMD "test -f ${LOCK_FILE}"; then
    echo "ERROR: lock file exists"
    exit 1
else
    $SSH_CMD "touch ${LOCK_FILE}" || exit_error "ERROR: can't create lock file"
fi

# Create or clean working directory
$SSH_CMD "mkdir -p ${WORK_DIR}; rm -rf ${WORK_DIR}/*" \
    || exit_error "ERROR: can't prepare workdir"

# Send repozitory to deploy server
tar --exclude-vcs --create --gzip --preserve-permissions --file - . \
    | $SSH_CMD "tar --directory ${WORK_DIR} --extract --gzip --preserve-permissions --file -" \
    || exit_error "ERROR: can't copy repository"

# Run provisioner.sh script
$SSH_CMD "cd ${WORK_DIR} && ./provisioner.sh inventories/staging" \
    || exit_error "ERROR on provisioner step"

# Run ansible playbook
$SSH_CMD "cd ${WORK_DIR} && ansible-playbook -i inventories/staging site.yaml" \
    || exit_error "ERROR on ansible step"

# Remove staging droplets
$SSH_CMD "cd ${WORK_DIR} && ./provisioner.sh inventories/staging deleted"

# Remove lock file
$SSH_CMD "rm ${LOCK_FILE}"

