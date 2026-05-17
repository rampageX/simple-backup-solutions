#!/bin/bash

# @author    Spas Z. Spasov <spas.z.spasov@metalevel.tech>
# @copyright 2024 Spas Z. Spasov
# @license   MIT License https://github.com/metalevel-tech/simple-backup-solutions/blob/master/LICENSE
#
# @desc      Create a local backup of a remote LXCs, create a local backup of the remote LXD's settings,
#            fetch other backup files.

TODAY="$(date +%Y-%m-%d)"

## Get the backup
BACKUP_DIR="/mnt/backup/portable/Contabo-VPS-PortableBackup"
LOG="$BACKUP_DIR/portable.backup.log"

SSH_HOST="cvps.metalevel.tech.forward.lxd"
REMOTE_LXD="cvps.metalevel.tech"
SYSTEM=$REMOTE_LXD
TEST_LXC_CONTAINER="portainer" # Set to "" if you do not need such test
REMOTE_BACKUP_DIR="/home/backups"

[[ ! -d $BACKUP_DIR ]] && mkdir "$BACKUP_DIR"

main_ssh_export() {
  echo -e "***** $TODAY *****\n"
  find "$BACKUP_DIR" -mtime +14 -type f -delete

  # Establish a connection to the remote server
  while ! (netstat -tnpau 2>/dev/null | grep -iPq -- 'tcp.*:8443.*LISTEN'); do
    echo "Starting: sshfwd-cvps.service..."
    systemctl start sshfwd-cvps.service
  done

  # Test the connection
  while ! (/snap/bin/lxc list "${REMOTE_LXD}:" -f csv -c n 2>/dev/null | grep -q "${TEST_LXC_CONTAINER}"); do
    /snap/bin/lxc remote list
    echo "Wait..."
    sleep 1
  done

  # Export all containers, if the both aboves tests pass
  if (netstat -tnpau 2>/dev/null | grep -iPq -- 'tcp.*:8443.*LISTEN') && (/snap/bin/lxc list -f csv -c n 2>/dev/null | grep -q "${TEST_LXC_CONTAINER}"); then
    echo "Exporting containers from '${REMOTE_LXD}'"
    for LXC in $(/snap/bin/lxc list -f csv -c n); do
      echo "Export '${LXC}'"
      BACKUP_FILE_LXC="${BACKUP_DIR}/${SYSTEM}-${TODAY}.lxc-${LXC}-export.tar.gz"
      echo -e "Export ${REMOTE_LXD}:${LXC} >\n\t ${BACKUP_FILE_LXC}"
      /snap/bin/lxc export "${REMOTE_LXD}:${LXC}" "$BACKUP_FILE_LXC"
    done
  else
    echo "Failed to establish a connection to the remote server"
    exit 1
  fi

  sleep 3

  # Dump the LXD configuration.
  # It is done in this way by intention. Otherwise, when we do a dump via
  # the remote management, some parameters as 'core.https_address: :8443' will be omitted.
  BACKUP_FILE_LXD="${BACKUP_DIR}/${SYSTEM}-${TODAY}.lxd-init-backup.yaml"
  ssh "${SSH_HOST}" 'lxd init --dump' >"$BACKUP_FILE_LXD"

  # Download the remote portable backup
  rsync --progress -avr -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" "${SSH_HOST}:${REMOTE_BACKUP_DIR}/"* "${BACKUP_DIR}/"

  echo -e "\n******************\n"
}
main_ssh_export #> "$LOG" 2>&1

exit
