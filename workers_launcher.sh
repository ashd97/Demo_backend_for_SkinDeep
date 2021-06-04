#!/bin/bash

#####################################################################
#
#   This code is under MIT license ashd97, hcl14
#
#   Script will preconfigure Ubuntu for multithread shworker, it will launch threads per cpu core.
#
#   tested on Ubuntu 20.04 
# 
#####################################################################


export WORKER_DB="sh_db0_dev"
export WORKER_USER="shworker"
export WORKER_PASSWORD="shworker"
export WORKER_DB_HOST="172.31.64.14"
export WORKER_GRID="receptor-grid_site2.zip"

# export WORKER_DB_HOST="127.0.0.1"


function run_one_pipeline () {

while true; do
    node_ip=$(hostname -I | cut -d' ' -f1)

    touch /home/ubuntu/shworker_${node_ip}.log

    cd /home/ubuntu/shworker/worker_postgres

    python3 /home/ubuntu/shworker/worker_postgres/pipeline.py |\
        gawk '{ print strftime("%b %d %H:%M:%S") " thread=" "'$1'" " node=" "'$node_ip'" " " , $0 }' >> /home/ubuntu/shworker_${node_ip}.log
done

}


main () {

if ! [ $(id -u) = 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# crontab -l | { cat; echo "@reboot /opt/shworker/shworker/worker_postgres/workers_launcher.sh"; } | crontab -

apt-get update

apt-get  --assume-yes install nfs-common nmap mutt screen mtr htop atop rsync rsyslog git postgresql-client-12

port_status=$(sudo nmap -PN -p 2049 -sN $WORKER_DB_HOST | grep 2049)

if [[ $port_status =~ "open" ]]
then

    sed -i '/workers_launcher.sh/d' /var/spool/cron/crontabs/root
    echo "@reboot /bin/bash /home/ubuntu/workers_launcher.sh" | tee -a /var/spool/cron/crontabs/root

    mkdir -p /opt/shworker
    mount -vv -t nfs4 -o ro,proto=tcp,vers=4.1,port=2049 $WORKER_DB_HOST:/opt/shworker   /opt/shworker

    # git clone https://github.com/Apex-Qubit/shworker

    mkdir -p /home/ubuntu/shworker
    cp -r /opt/shworker/shworker /home/ubuntu/

    source /opt/shworker/schrodinger.ve2/bin/activate
    # python3 /opt/shworker/mmshare-v5.1/python/scripts/schrodinger_virtualenv.py schrodinger.ve

    number_of_threads=$(grep -c ^processor /proc/cpuinfo)

    for i in $(seq $number_of_threads); do
        sleep 2
        run_one_pipeline $i &
    done

else
    echo "Port 2049 is closed. You need to recheck firewall on the database host."
    exit 1
fi

}

main "$@"

