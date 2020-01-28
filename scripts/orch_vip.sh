#!/bin/bash

function usage {
  cat << EOF
 usage: $0 [-h] [-o old master ] [-s ssh options] [-n new master] [-i interface] [-I] [-g gateway] [-u SSH user]
 
 OPTIONS:
    -h        Show this message
    -o string Old master hostname or IP address 
    -s string SSH options
    -n string New master hostname or IP address
    -i string Interface, e.g. eth0:0
    -I string Virtual IP
    -g string Subnet gateway 
    -u string SSH user
EOF

}

while getopts ho:s:n:i:I:g:u: flag; do
  case $flag in
    o)
      oldMaster="${OPTARG}";
      ;;
    s)
      sshOptions="${OPTARG}";
      ;;
    n)
      newMaster="${OPTARG}";
      ;;
    i)
      interface="${OPTARG}";
      ;;
    I)
      vip="${OPTARG}";
      ;;
    u)
      sshUser="${OPTARG}";
      ;;
    g)
      gateway="${OPTARG}"
    h)
      usage;
      exit 0;
      ;;
    *)
      usage;
      exit 1;
      ;;
  esac
done


if [ ${OPTIND} -eq 1 ]; then 
    echo "No options were passed"; 
    usage;
fi

shift $(( {OPTIND} - 1 ));

# command for adding our VIP
cmd_vip_add="ifconfig ${interface} ${vip} up"
# command for deleting our VIP
cmd_vip_del="ifconfig ${interface} down"
# command for discovering if our VIP is enabled
cmd_vip_chk="ifconfig | grep 'inet addr' | grep ${vip}"
# command for sending gratuitous ARP to announce IP move
cmd_arp_fix="arping -c 3 ${vip} ${gateway}"

vip_stop() {
    rc=0

    # ensure the VIP is removed
    ssh ${sshOptions} -tt ${sshUser}@${oldMaster} \
    "[ -n \"\$(${cmd_vip_chk})\" ] && ${cmd_vip_del} && ${cmd_arp_fix} || [ -z \"\$(${cmd_vip_chk})\" ]"

    rc=$?
    return ${rc}
}

vip_start() {
    rc=0

    # ensure the VIP is added
    # this command should exit with failure if we are unable to add the VIP
    # if the VIP already exists always exit 0 (whether or not we added it)
    ssh ${sshOptions} -tt ${sshUser}@${newMaster} \
     "[ -z \"\$(${cmd_vip_chk})\" ] && ${cmd_vip_add} && ${cmd_arp_fix} || [ -n \"\$(${cmd_vip_chk})\" ]"
    
    rc=$?
    return ${rc}
}

vip_status() {
    arping -c 2 ${vip}
    if ping -c 2 -W 1 ${vip}; then
        return 0
    else
        return 1
    fi
}

echo "[info] Master is dead, trying to move VIP from old master to a new one"

echo '[info] Make sure the VIP is not available...'
if vip_status; then 
    echo '[info] VIP is pingable so try to down it.'
    if vip_stop; then
        echo "[info] ${vip} is removed from ${oldMaster}."
    else
        echo "[info] Couldn't remove ${vip} from ${oldMaster}."
        exit 1
    fi
fi

echo '[info] Moving VIP to new master.'
if vip_start; then
      echo "[info] ${vip} is moved to ${newMaster}."
else
      echo "[info] Can't add ${vip} on ${newMaster}!" 
      exit 1
fi
