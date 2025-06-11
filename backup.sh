#!/bin/bash

# گرفتن توکن ربات
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ $tk == $'\0' ]]; then
        echo "Invalid input. Token cannot be empty."
        unset tk
    fi
done

# گرفتن Chat ID
while [[ -z "$chatid" ]]; do
    echo "Chat id: "
    read -r chatid
    if [[ $chatid == $'\0' ]]; then
        echo "Invalid input. Chat id cannot be empty."
        unset chatid
    elif [[ ! $chatid =~ ^\-?[0-9]+$ ]]; then
        echo "${chatid} is not a number."
        unset chatid
    fi
done

# گرفتن عنوان برای کپشن
echo "Caption (for example, your domain, to identify the database file more easily): "
read -r caption

# گرفتن زمان کرونجاب
while true; do
    echo "Cronjob (minutes and hours) (e.g : 30 6 or 0 12) : "
    read -r minute hour
    if [[ $minute == 0 ]] && [[ $hour == 0 ]]; then
        cron_time="* * * * *"
        break
    elif [[ $minute == 0 ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]]; then
        cron_time="0 */${hour} * * *"
        break
    elif [[ $hour == 0 ]] && [[ $minute =~ ^[0-9]+$ ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} * * * *"
        break
    elif [[ $minute =~ ^[0-9]+$ ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]] && [[ $minute -lt 60 ]]; then
        cron_time="${minute} ${hour} * * *"
        break
    else
        echo "Invalid input, please enter a valid cronjob format (minutes and hours, e.g: 0 6 or 30 12)"
    fi
done

# انتخاب نوع پنل بکاپ
while [[ -z "$xmh" ]]; do
    echo "Choose backup panel: x-ui, marzban, hiddify, or marzneshin? [x/m/h/n] : "
    read -r xmh
    if [[ $xmh == $'\0' ]]; then
        echo "Invalid input. Please choose x, m, h or n."
        unset xmh
    elif [[ ! $xmh =~ ^[xmhn]$ ]]; then
        echo "${xmh} is not a valid option. Please choose x, m, h or n."
        unset xmh
    fi
done

while [[ -z "$crontabs" ]]; do
    echo "Would you like the previous crontabs to be cleared? [y/n] : "
    read -r crontabs
    if [[ $crontabs == $'\0' ]]; then
        echo "Invalid input. Please choose y or n."
        unset crontabs
    elif [[ ! $crontabs =~ ^[yn]$ ]]; then
        echo "${crontabs} is not a valid option. Please choose y or n."
        unset crontabs
    fi
done

if [[ "$crontabs" == "y" ]]; then
    # حذف کرونجاب‌های قبلی مرتبط با بکاپ
    sudo crontab -l | grep -vE '/root/ac-backup.+\.sh' | crontab -
fi

# نصب zip اگر موجود نبود
sudo apt-get update
sudo apt-get install zip -y

# گرفتن آی‌پی سرور
IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')

trim() {
    # حذف فضای خالی ابتدا و انتها
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

case "$xmh" in
    m)  # marzban backup
        ACLover="marzban backup"

        if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
            echo "Marzban folder found at $dir"
        else
            echo "Marzban folder not found."
            exit 1
        fi

        if [ -d "/var/lib/marzban/mysql" ]; then
            sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env

            docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"
            source /opt/marzban/.env

            cat > "/var/lib/marzban/mysql/ac-backup.sh" <<EOL
#!/bin/bash
USER="root"
PASSWORD="$MYSQL_ROOT_PASSWORD"
databases=\$(mysql -h 127.0.0.1 --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]] ; then
        echo "Dumping database: \$db"
        mysqldump -h 127.0.0.1 --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /var/lib/mysql/db-backup/\$db.sql
    fi
done
EOL
            chmod +x /var/lib/marzban/mysql/ac-backup.sh

            ZIP=$(cat <<EOF
docker exec marzban-mysql-1 bash -c "/var/lib/mysql/ac-backup.sh"
zip -r /root/ac-backup-m.zip /opt/marzban/* /var/lib/marzban/* /opt/marzban/.env -x /var/lib/marzban/mysql/\*
zip -r /root/ac-backup-m.zip /var/lib/marzban/mysql/db-backup/*
rm -rf /var/lib/marzban/mysql/db-backup/*
EOF
)
        else
            ZIP="zip -r /root/ac-backup-m.zip ${dir}/* /var/lib/marzban/* /opt/marzban/.env"
        fi
        ;;

    x)  # x-ui backup
        ACLover="x-ui backup"

        if dbDir=$(find /etc /opt/freedom -type d -iname "x-ui*" -print -quit); then
            echo "x-ui folder found at $dbDir"
            if [[ $dbDir == *"/opt/freedom/x-ui"* ]]; then
                dbDir="${dbDir}/db/"
            fi
        else
            echo "x-ui folder not found."
            exit 1
        fi

        if configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit); then
            echo "x-ui config folder found at $configDir"
        else
            echo "x-ui config folder not found."
            exit 1
        fi

        ZIP="zip /root/ac-backup-x.zip ${dbDir}/x-ui.db ${configDir}/config.json"
        ;;

    h)  # hiddify backup
        ACLover="hiddify backup"

        if ! find /opt/hiddify-manager/hiddify-panel/ -type d -iname "backup" -print -quit; then
            echo "hiddify backup folder not found."
            exit 1
        fi

        ZIP=$(cat <<EOF
cd /opt/hiddify-manager/hiddify-panel/
if [ \$(find /opt/hiddify-manager/hiddify-panel/backup -type f | wc -l) -gt 100 ]; then
    find /opt/hiddify-manager/hiddify-panel/backup -type f -delete
fi
python3 -m hiddifypanel backup
cd /opt/hiddify-manager/hiddify-panel/backup
latest_file=\$(ls -t *.json | head -n1)
rm -f /root/ac-backup-h.zip
zip /root/ac-backup-h.zip /opt/hiddify-manager/hiddify-panel/backup/\$latest_file
EOF
)
        ;;

    n)  # marzneshin backup
        ACLover="marzneshin backup"

        if dir=$(find /etc/opt /var/lib -type d -iname "marzneshin" -print -quit); then
            echo "Marzneshin folder found at $dir"
        else
            echo "Marzneshin folder not found."
            exit 1
        fi

        if [ -d "/var/lib/marzneshin/mysql" ]; then
            sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /etc/opt/marzneshin/.env

            docker exec marzneshin-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"
            source /etc/opt/marzneshin/.env

            cat > "/var/lib/marzneshin/mysql/ac-backup.sh" <<EOL
#!/bin/bash
USER="root"
PASSWORD="$MYSQL_ROOT_PASSWORD"
databases=\$(mysql -h 127.0.0.1 --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]] ; then
        echo "Dumping database: \$db"
        mysqldump -h 127.0.0.1 --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /var/lib/mysql/db-backup/\$db.sql
    fi
done
EOL
            chmod +x /var/lib/marzneshin/mysql/ac-backup.sh

            ZIP=$(cat <<EOF
docker exec marzneshin-mysql-1 bash -c "/var/lib/mysql/ac-backup.sh"
zip -r /root/ac-backup-n.zip /etc/opt/marzneshin/* /var/lib/marzneshin/* /var/lib/marznode/*
zip -r /root/ac-backup-n.zip /var/lib/marzneshin/mysql/db-backup/*
rm -rf /var/lib/marzneshin/mysql/db-backup/*
EOF
)
        else
            ZIP="zip -r /root/ac-backup-n.zip ${dir}/* /var/lib/marzneshin/* /var/lib/marznode/*"
        fi
        ;;

    *)
        echo "Please choose one of x, m, h, or n only!"
        exit 1
        ;;
esac

caption="${caption}\n\n${ACLover}\n<code>${IP}</code>\nCreated by @Pv_VEnZo - https://github.com/My-VEnZo/backup"
comment=$(echo -e "$caption" | sed 's/<code>//g;s/<\/code>//g')
comment=$(trim "$comment")

# ساخت اسکریپت اصلی بکاپ
cat > "/root/ac-backup-${xmh}.sh" <<EOL
#!/bin/bash
rm -f /root/ac-backup-${xmh}.zip
$ZIP
echo -e "$comment"
curl -s "https://api.telegram.org/bot$tk/sendDocument" -F chat_id=$chatid -F document="@/root/ac-backup-${xmh}.zip" -F caption="$caption" -F parse_mode="HTML"
rm -f /root/ac-backup-${xmh}.zip
EOL

chmod +x "/root/ac-backup-${xmh}.sh"

# تنظیم کرونجاب
(crontab -l 2>/dev/null; echo "$cron_time /root/ac-backup-${xmh}.sh") | crontab -

echo "Cronjob set for $cron_time to run /root/ac-backup-${xmh}.sh"
