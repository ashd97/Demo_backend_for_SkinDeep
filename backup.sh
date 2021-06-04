#!/bin/bash

#####################################################################
#   Small email backup script. 
#
#   Check cat ~/.muttrc first.
#
#    set from = "ApexQubit@gmail.com"
#    set realname = "shworker news"
#
#    # My credentials
#    set smtp_url="smtps://ApexQubit@gmail.com@smtp.gmail.com:465/"
#    set smtp_pass = "******"
#
#    #  bash generate random number between 0 and 9
#    #  $(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
#
#    # My mailboxes
#    set folder = ""
#    set spoolfile = "+INBOX"
#
#####################################################################

subject='Daily report message'

node_ip=$(hostname -I | cut -d' ' -f1)
    
time=$(date '+%b_%d_%H_%M_%S')

cat <<EOF > emails.txt
savely.kanevsky@gmail.com
egbeliaev@gmail.com
EOF

main () {

    sudo -i -u postgres pg_dump -d sh_db0_dev --column-inserts --data-only --table=files.files > /tmp/files_backup_${node_ip}_${time}.sql
    bzip2 /tmp/files_backup_${node_ip}_${time}.sql
    
    mkdir -p /home/ubuntu/database_backups
    mv /tmp/files_backup_${node_ip}_${time}.sql.bz2 /home/ubuntu/database_backups
    touch /home/ubuntu/database_backups/Files.csv
    chmod 777 /home/ubuntu/database_backups/Files.csv
    
    echo "
        COPY (
            SELECT id, docking_score, num_conformers, smiles 
            FROM files.files
            WHERE docking_score IS NOT NULL
            ORDER BY docking_score, created_ts DESC
        ) TO '/home/ubuntu/database_backups/Files.csv' WITH CSV DELIMITER ',' HEADER;
    " | sudo -i -u postgres psql -qtAx -U postgres -d sh_db0_dev
    
    mv /home/ubuntu/database_backups/Files.csv /home/ubuntu/database_backups/Files_${time}.csv
    
    
    report='/home/ubuntu/database_backups/report.html'
    truncate -s 0 $report
    
    printf '<style type="text/css"> body, table, td {font-family: Arial, Helvetica, sans-serif !important; font-size:12px; line-height: normal;} </style>' >> $report
    printf '<!--[if mso]> <style type="text/css"> body, table, td {font-family: Arial, Helvetica, sans-serif !important; font-size:12px; line-height: normal;} </style> <![endif]-->' >> $report
    printf '<body> Report message from shworker database server <p></p>\n' >> $report
    
    echo ' 	SELECT  files.extrapolation(0); ' | psql -qtAx -U debugger -d sh_db0_dev |\
        gawk '{ print "Dear user, Amazon group of shworkers will dock will finish processing molecules in (hours) -" , $0 ,"\n" }' >> $report
    
    printf 'Below some info about the active workers, pls note that it is not completely accurate <p></p>\n' >> $report
    
    psql -U debugger -c "select * from active_workers;" -d sh_db0_dev -H | sed '/rows/d'>> $report
    
    while IFS="" read -r p || [ -n "$p" ]
        do
            if [ "$p" ];then
            mutt -s "$subject" "$p" \
            -e "set content_type=text/html" \
            < $report \
            -a /home/ubuntu/database_backups/files_backup_${node_ip}_${time}.sql.bz2 -a /home/ubuntu/database_backups/Files_${time}.csv
            fi
        done < emails.txt
    
    truncate -s 0 emails.txt
}

main "$@"
