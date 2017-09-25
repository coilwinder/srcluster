#!/bin/bash -xv

LOCK_FILE='/home/ansible/.sr_lock'
WORK_DIR='/home/ansible/srwork'
SSH_STR='ansible@46.101.218.33'
SSH_CMD="ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_STR}"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin


if $SSH_CMD "test -f ${LOCK_FILE}"
then
    echo "Error: lock file exists"
    exit 1
fi

$SSH_CMD "touch ${LOCK_FILE}" || exit_error "ERROR can't create lock file"

function exit_error ()
{
   MSG="$1"
   $SSH_CMD "cd ${WORK_DIR}; ./provisioner.sh inventories/staging deleted"
   echo "${MSG}"
   $SSH_CMD "rm ${LOCK_FILE}"
   exit 1
}

trap "exit_error 'ERROR: exit by signal'" ERR SIGINT SIGTERM

$SSH_CMD "mkdir -p ${WORK_DIR}; rm -rf ${WORK_DIR}/*" || exit_error "ERROR can't prepare workdir"

tar -czp --exclude-vcs --file - . | $SSH_CMD "tar xzp --file - -C ${WORK_DIR}" || exit_error "ERROR can't copy "
$SSH_CMD "cd ${WORK_DIR}; env; ls -la; echo "

$SSH_CMD "cd ${WORK_DIR}; ./provisioner.sh inventories/staging/"  || exit_error "ERROR on staging.provisioner step"
$SSH_CMD "cd ${WORK_DIR}; ansible-playbook -i inventories/staging site.yaml" || exit_error "ERROR on staging.ansible step"
$SSH_CMD "cd ${WORK_DIR}; ./provisioner.sh inventories/staging/ deleted"

SSH_CMD "rm ${LOCK_FILE}"

