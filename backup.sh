#!/bin/bash

# گرفتن توکن ربات تلگرام
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
done

# گرفتن Chat ID
while [[ -z "$chatid" ]]; do
    echo "Chat id: "
    read -r chatid
done

# گرفتن عنوان کپشن فایل بکاپ
echo "Caption (مثلا نام دامنه یا توضیح): "
read -r caption

# گرفتن زمان کرونجاب (دقیقه و ساعت)
while true; do
    echo "Cronjob (minutes hours) (مثلا: 30 6 یا 0 12): "
    read -r minute hour
    if [[ $minute == 0 && $hour == 0 ]]; then
        cron_time="* * * * *"
        break
    elif [[ $minute == 0 && $hour =~ ^[0-9]+$ && $hour -lt 24 ]]; then
        cron_time="0 */${hour} * * *"
        break
    elif [[ $hour == 0 && $minute =~ ^[0-9]+$ && $minute -lt 60 ]]; then
        cron_time="*/${minute} * * * *"
        break
    elif [[ $minute =~ ^[0-9]+$ && $hour =~ ^[0-9]+$ && $hour -lt 24 && $minute -lt 60 ]]; then
        cron_time="${minute} ${hour} * * *"
        break
    else
        echo "فرمت کرونجاب اشتباه است، دوباره وارد کنید."
    fi
done

# گرفتن نام پنل (x-ui, marzban, hiddify, marzneshin)
while [[ -z "$xmh" ]]; do
    echo "کدام پنل؟ [x] X-UI, [m] Marzban, [h] Hiddify, [n] Marzneshin : "
    read -r xmh
    if [[ ! "$xmh" =~ ^[xmh n]$ ]]; then
        echo "فقط یکی از حروف x, m, h, n را وارد کنید."
        unset xmh
    fi
done

# پاک کردن کرونجاب‌های قبلی مربوط به این اسکریپت
while [[ -z "$crontabs" ]]; do
    echo "می‌خواهید کرونجاب‌های قبلی پاک شود؟ [y/n]: "
    read -r crontabs
    if [[ ! "$crontabs" =~ ^[yn]$ ]]; then
        echo "فقط y یا n را وارد کنید."
        unset crontabs
    fi
done

if [[ "$crontabs" == "y" ]]; then
    sudo crontab -l | grep -vE '/root/ac-backup.+\.sh' | sudo crontab -
fi

# نصب zip اگر نبود
sudo apt install zip -y

# شروع ساخت بکاپ با توجه به پنل انتخاب شده
if [[ "$xmh" == "m" ]]; then
    # Marzban
    if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
        echo "پوشه Marzban در $dir یافت شد."
    else
        echo "پوشه Marzban یافت نشد."
        exit 1
    fi

    if [ -d "/var/lib/marzban/mysql" ]; then
        sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env
        source /opt/marzban/.env

        docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"
        cat > "/var/lib/marzban/mysql/ac-backup.sh" <<EOL
#!/bin/bash
USER="root"
PASSWORD="$MYSQL_ROOT_PASSWORD"
databases=\$(mysql -h 127.0.0.1 --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]]; then
        echo "Dumping database: \$db"
        mysqldump -h 127.0.0.1 --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /var/lib/mysql/db-backup/\$db.sql
    fi
done
EOL
        chmod +x /var/lib/marzban/mysql/ac-backup.sh

        ZIP=$(cat <<EOF
docker exec marzban-mysql-1 bash -c "/var/lib/mysql/ac-backup.sh"
zip -r /root/ac-backup-m.zip /opt/marzban/* /var/lib/marzban/* /opt/marzban/.env -x /var/lib/marzban/mysql/*
zip -r /root/ac-backup-m.zip /var/lib/marzban/mysql/db-backup/*
rm -rf /var/lib/marzban/mysql/db-backup/*
EOF
)
    else
        ZIP="zip -r /root/ac-backup-m.zip ${dir}/* /var/lib/marzban/* /opt/marzban/.env"
    fi

    ACLover="Marzban Backup"

elif [[ "$xmh" == "x" ]]; then
    # X-UI
    if dbDir=$(find /etc /opt/freedom -type d -iname "x-ui*" -print -quit); then
        echo "پوشه دیتابیس X-UI در $dbDir یافت شد."
        if [[ $dbDir == *"/opt/freedom/x-ui"* ]]; then
            dbDir="${dbDir}/db/"
        fi
    else
        echo "پوشه دیتابیس X-UI یافت نشد."
        exit 1
    fi

    if configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit); then
        echo "پوشه کانفیگ X-UI در $configDir یافت شد."
    else
        echo "پوشه کانفیگ X-UI یافت نشد."
        exit 1
    fi

    ZIP="zip /root/ac-backup-x.zip ${dbDir}/x-ui.db ${configDir}/config.json"
    ACLover="X-UI Backup"

elif [[ "$xmh" == "h" ]]; then
    # Hiddify
    if ! find /opt/hiddify-manager/hiddify-panel/ -type d -iname "backup" -print -quit; then
        echo "پوشه بکاپ Hiddify یافت نشد."
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
    ACLover="Hiddify Backup"

elif [[ "$xmh" == "n" ]]; then
    # Marzneshin
    if [ -d "/var/lib/marzneshin/mysql" ]; then
        sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /etc/opt/marzneshin/.env
        source /etc/opt/marzneshin/.env

        docker exec marzneshin-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"
        cat > "/var/lib/marzneshin/mysql/ac-backup.sh" <<EOL
#!/bin/bash
USER="root"
PASSWORD="$MYSQL_ROOT_PASSWORD"
databases=\$(mysql -h 127.0.0.1 --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]]; then
        echo "Dumping database: \$db"
        mysqldump -h 127.0.0.1 --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /var/lib/mysql/db-backup/\$db.sql
    fi
done
EOL
        chmod +x /var/lib/marzneshin/mysql/ac-backup.sh

        ZIP=$(cat <<EOF
docker exec marzneshin-mysql-1 bash -c "/var/lib/mysql/ac-backup.sh"
zip -r /root/ac-backup-ns.zip /etc/opt/marzneshin/* /var/lib/marzneshin/* /var/lib/marznode/* -x /var/lib/marzneshin/mysql/*
zip -r /root/ac-backup-ns.zip /var/lib/marzneshin/mysql/db-backup/*
rm -rf /var/lib/marzneshin/mysql/db-backup/*
EOF
)
    else
        ZIP="zip -r /root/ac-backup-ns.zip /etc/opt/marzneshin/* /var/lib/marzneshin/* /var/lib/marznode/*"
    fi

    ACLover="Marzneshin Backup"

else
    echo "لطفا فقط یکی از گزینه‌های x, m, h, n را وارد کنید."
    exit 1
fi

trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\n${ACLover}\n<code>${IP}</code>\nCreated by @AC_Lover - https://github.com/AC-Lover"

# ساخت فایل اسکریپت بکاپ
cat > "/root/ac-backup-$xmh.sh" <<EOF
#!/bin/bash
$ZIP
EOF

chmod +x "/root/ac-backup-$xmh.sh"

# اضافه کردن کرونجاب
(crontab -l 2>/dev/null; echo "$cron_time root /root/ac-backup-$xmh.sh && curl -s -X POST https://api.telegram.org/bot$tk/sendDocument -F chat_id=$chatid -F document=@/root/ac-backup-$xmh.zip -F caption='$caption'") | crontab -

echo "کرونجاب با موفقیت اضافه شد."
echo "اسکریپت بکاپ در /root/ac-backup-$xmh.sh ساخته شد."
echo "بکاپ با عنوان $ACLover آماده می‌شود."
