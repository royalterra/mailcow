textb() { echo $(tput bold)${1}$(tput sgr0); }
greenb() { echo $(tput bold)$(tput setaf 2)${1}$(tput sgr0); }
redb() { echo $(tput bold)$(tput setaf 1)${1}$(tput sgr0); }
yellowb() { echo $(tput bold)$(tput setaf 3)${1}$(tput sgr0); }


genpasswd() {
    count=0
    while [ $count -lt 3 ]
    do
        pw_valid=$(tr -cd A-Za-z0-9 < /dev/urandom | fold -w24 | head -n1)
        count=$(grep -o "[0-9]" <<< $pw_valid | wc -l)
    done
    echo $pw_valid
}

returnwait() {
	echo
    echo "$1 - $(greenb [OK])";
    echo "Proceeding with $(textb "$2")"
	if [[ $inst_unattended != "yes" ]]; then
		read -p "Press ENTER to continue or CTRL-C to cancel installation"
	fi
	echo
}

is_ipv6() {
    # Thanks to https://github.com/mutax
    INPUT="$@"
    O=""
    while [ "$O" != "$INPUT" ]; do
        O="$INPUT"
        INPUT="$( sed  's|:\([0-9a-f]\{3\}\):|:0\1:|g' <<< "$INPUT" )"
        INPUT="$( sed  's|:\([0-9a-f]\{3\}\)$|:0\1|g'  <<< "$INPUT")"
        INPUT="$( sed  's|^\([0-9a-f]\{3\}\):|0\1:|g'  <<< "$INPUT" )"
        INPUT="$( sed  's|:\([0-9a-f]\{2\}\):|:00\1:|g' <<< "$INPUT")"
        INPUT="$( sed  's|:\([0-9a-f]\{2\}\)$|:00\1|g'  <<< "$INPUT")"
        INPUT="$( sed  's|^\([0-9a-f]\{2\}\):|00\1:|g'  <<< "$INPUT")"
        INPUT="$( sed  's|:\([0-9a-f]\):|:000\1:|g'  <<< "$INPUT")"
        INPUT="$( sed  's|:\([0-9a-f]\)$|:000\1|g'   <<< "$INPUT")"
        INPUT="$( sed  's|^\([0-9a-f]\):|000\1:|g'   <<< "$INPUT")"
    done

    grep -qs "::" <<< "$INPUT"
    if [ "$?" -eq 0 ]; then
        GRPS="$(sed  's|[0-9a-f]||g' <<< "$INPUT" | wc -m)"
        ((GRPS--)) # carriage return
        ((MISSING=8-GRPS))
        for ((i=0;i<$MISSING;i++)); do
            ZEROES="$ZEROES:0000"
        done
        INPUT="$( sed  's|\(.\)::\(.\)|\1'$ZEROES':\2|g'   <<< "$INPUT")"
        INPUT="$( sed  's|\(.\)::$|\1'$ZEROES':0000|g'   <<< "$INPUT")"
        INPUT="$( sed  's|^::\(.\)|'$ZEROES':0000:\1|g;s|^:||g'   <<< "$INPUT")"
    fi

    if [ $(echo $INPUT | wc -m) != 40 ]; then
        return 1
    else
        return 0
    fi
}

checkports() {
	for port in 25 80 143 443 465 587 993 995
	do
	    if [[ ! -z $(lsof -iTCP:$port) ]]; then
	        echo "$(redb [ERR]) - An application is blocking the installation on Port $(textb $port)"
	        lsof -iTCP:$port
	        echo
			# Wait until finished to list all blocked ports.
			blocked_port=1
	    fi
	done
	[[ $blocked_port -eq 1 ]] && exit 1
}

checkconfig() {
    if [[ $conf_done = "no" ]]; then
        echo "$(redb [ERR]) - Error in configuration file"
        echo "Is \"conf_done\" set to \"yes\"?"
        echo
        exit 1
    elif [[ ${#cert_country} -ne 2 ]]; then
        echo "$(redb [ERR]) - Country code must contain exactly two characters"
        exit 1
    else
    for var in sys_hostname sys_domain sys_timezone my_postfixdb my_postfixuser my_postfixpass my_rootpw my_rcuser my_rcpass my_rcdb pfadmin_adminuser pfadmin_adminpass cert_country cert_state cert_city cert_org
    do
        if [[ -z ${!var} ]]; then
            echo "$(redb [ERR]) - Parameter $var must not be empty."
            echo
            exit 1
        fi
    done
    fi
    pass_count=$(grep -o "[0-9]" <<< $pfadmin_adminpass | wc -l)
    pass_chars=$(echo $pfadmin_adminpass | egrep "^.{8,255}" | \
        egrep "[ABCDEFGHIJKLMNOPQRSTUVXYZ]" | \
        egrep "[abcdefghijklmnopqrstuvxyz"] | \
        egrep "[0-9]")
    if [[ $pass_count -lt 2 || -z $pass_chars ]]; then
            echo "$(redb [ERR]) - Postfixadmin password does not meet password policy requirements."
            echo
            exit 1
    fi
}

installtask() {
	case $1 in
		environment)
			getpublicipv4=$(wget -q4O- ip4.telize.com)
			if [[ $getpublicipv4 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
				cat > /etc/hosts<<'EOF'
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
			echo $getpublicipv4 $sys_hostname.$sys_domain $sys_hostname >> /etc/hosts
			echo $sys_hostname.$sys_domain > /etc/mailname
			getpublicipv6=$(wget -t2 -T1 -q6O- ip6.telize.com)
            if is_ipv6 $getpublicipv6; then
				 echo $getpublicipv6 $sys_hostname.$sys_domain $sys_hostname >> /etc/hosts
			fi
			echo $sys_hostname > /etc/hostname
			service hostname.sh start
			else
				echo "$(yellowb WARNING): Cannot set your hostname"
			fi
			if [[ -f /usr/share/zoneinfo/$sys_timezone ]] ; then
				echo $sys_timezone > /etc/timezone
				dpkg-reconfigure -f noninteractive tzdata
			else
				echo "$(yellowb WARNING): Cannot set your timezone: timezone is unknown";
			fi
			;;
		installpackages)
			echo "Installing packages unattended, please stand by, errors will be reported."
apt-get -y update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get --force-yes -y install dnsutils python-sqlalchemy python-beautifulsoup python-setuptools \
python-magic openssl php-auth-sasl php-http-request php-mail php-mail-mime php-mail-mimedecode php-net-dime php-net-smtp \
php-net-socket php-net-url php-pear php-soap php5 php5-cli php5-common php5-curl php5-fpm php5-gd php5-imap php-apc subversion \
php5-intl php5-mcrypt php5-mysql php5-sqlite libawl-php php5-xmlrpc mysql-client mysql-server nginx-extras dovecot-common dovecot-core mailutils \
dovecot-imapd dovecot-lmtpd dovecot-managesieved dovecot-sieve dovecot-mysql dovecot-pop3d postfix \
postfix-mysql postfix-pcre clamav clamav-base clamav-daemon clamav-freshclam spamassassin  >/dev/null
			;;
		ssl)
			mkdir /etc/ssl/mail
			openssl req -new -newkey rsa:4096 -days 1095 -nodes -x509 -subj "/C=$cert_country/ST=$cert_state/L=$cert_city/O=$cert_org/CN=$sys_hostname.$sys_domain" -keyout /etc/ssl/mail/mail.key  -out /etc/ssl/mail/mail.crt
			chmod 600 /etc/ssl/mail/mail.key
			;;
		mysql)
			mysql --defaults-file=/etc/mysql/debian.cnf -e "UPDATE mysql.user SET Password=PASSWORD('$my_rootpw') WHERE USER='root'; FLUSH PRIVILEGES;"
			mysql --defaults-file=/etc/mysql/debian.cnf -e "DROP DATABASE IF EXISTS $my_postfixdb; DROP DATABASE IF EXISTS $my_rcdb;"
			mysql --defaults-file=/etc/mysql/debian.cnf -e "CREATE DATABASE $my_postfixdb; GRANT ALL PRIVILEGES ON $my_postfixdb.* TO '$my_postfixuser'@'localhost' IDENTIFIED BY '$my_postfixpass';"
            mysql --defaults-file=/etc/mysql/debian.cnf -e "CREATE DATABASE $my_rcdb; GRANT ALL PRIVILEGES ON $my_rcdb.* TO '$my_rcuser'@'localhost' IDENTIFIED BY '$my_rcpass';"
			;;
		fuglu)
			mkdir /var/log/fuglu 2> /dev/null
			groupadd fuglu
			useradd -g fuglu -s /bin/false fuglu
			usermod -a -G debian-spamd fuglu
			usermod -a -G clamav fuglu
			rm /tmp/fuglu_control.sock 2> /dev/null
			chown fuglu:fuglu /var/log/fuglu
			tar xf fuglu/inst/$fuglu_version.tar -C fuglu/inst/ 2> /dev/null
			(cd fuglu/inst/$fuglu_version ; python setup.py -q install)
			cp -R fuglu/conf/* /etc/fuglu/
			cp fuglu/inst/$fuglu_version/scripts/startscripts/debian/7/fuglu /etc/init.d/fuglu
			chmod +x /etc/init.d/fuglu
			update-rc.d fuglu defaults
			rm -rf fuglu/inst/$fuglu_version
			;;
		postfix)
			cp -R postfix/conf/* /etc/postfix/
			chown root:postfix "/etc/postfix/sql/mysql_virtual_alias_domain_catchall_maps.cf"; chmod 640 "/etc/postfix/sql/mysql_virtual_alias_domain_catchall_maps.cf"
			chown root:postfix "/etc/postfix/sql/mysql_virtual_alias_maps.cf"; chmod 640 "/etc/postfix/sql/mysql_virtual_alias_maps.cf"
			chown root:postfix "/etc/postfix/sql/mysql_virtual_alias_domain_mailbox_maps.cf"; chmod 640 "/etc/postfix/sql/mysql_virtual_alias_domain_mailbox_maps.cf"
			chown root:postfix "/etc/postfix/sql/mysql_virtual_mailbox_limit_maps.cf"; chmod 640 "/etc/postfix/sql/mysql_virtual_mailbox_limit_maps.cf"
			chown root:postfix "/etc/postfix/sql/mysql_virtual_mailbox_maps.cf"; chmod 640 "/etc/postfix/sql/mysql_virtual_mailbox_maps.cf"
			chown root:postfix "/etc/postfix/sql/mysql_virtual_alias_domain_maps.cf"; chmod 640 "/etc/postfix/sql/mysql_virtual_alias_domain_maps.cf"
			chown root:postfix "/etc/postfix/sql/mysql_virtual_domains_maps.cf"; chmod 640 "/etc/postfix/sql/mysql_virtual_domains_maps.cf"
			chown root:root "/etc/postfix/master.cf"; chmod 644 "/etc/postfix/master.cf"
			chown root:root "/etc/postfix/main.cf"; chmod 644 "/etc/postfix/main.cf"
			sed -i "s/mail.domain.tld/$sys_hostname.$sys_domain/g" /etc/postfix/* 2> /dev/null
			sed -i "s/domain.tld/$sys_domain/g" /etc/postfix/* 2> /dev/null
			sed -i "s/my_postfixpass/$my_postfixpass/g" /etc/postfix/sql/*
			sed -i "s/my_postfixuser/$my_postfixuser/g" /etc/postfix/sql/*
			sed -i "s/my_postfixdb/$my_postfixdb/g" /etc/postfix/sql/*
			;;
		dovecot)
			rm -rf /etc/dovecot/* 2> /dev/null
			cp -R dovecot/conf/*.conf /etc/dovecot/
			groupadd -g 5000 vmail
			useradd -g vmail -u 5000 vmail -d /var/vmail
			chown root:dovecot "/etc/dovecot/dovecot-dict-sql.conf"; chmod 640 "/etc/dovecot/dovecot-dict-sql.conf"
			chown root:vmail "/etc/dovecot/dovecot-mysql.conf"; chmod 640 "/etc/dovecot/dovecot-mysql.conf"
			chown root:root "/etc/dovecot/dovecot.conf"; chmod 644 "/etc/dovecot/dovecot.conf"
			sed -i "s/mail.domain.tld/$sys_hostname.$sys_domain/g" /etc/dovecot/*
			sed -i "s/domain.tld/$sys_domain/g" /etc/dovecot/*
			sed -i "s/my_postfixpass/$my_postfixpass/g" /etc/dovecot/*
			sed -i "s/my_postfixuser/$my_postfixuser/g" /etc/dovecot/*
			sed -i "s/my_postfixdb/$my_postfixdb/g" /etc/dovecot/*
			mkdir -p /var/vmail/sieve
			cp dovecot/conf/spam-global.sieve /var/vmail/sieve/spam-global.sieve
			cp dovecot/conf/default.sieve /var/vmail/sieve/default.sieve
			sievec /var/vmail/sieve/spam-global.sieve
			chown -R vmail:vmail /var/vmail
			cp dovecot/conf/doverecalcq /etc/cron.daily/; chmod 755 /etc/cron.daily/doverecalcq
			;;
		clamav)
			service clamav-daemon stop
			service clamav-freshclam stop
			freshclam
			sed -i '/MaxFileSize/c\MaxFileSize 25M' /etc/clamav/clamd.conf
			sed -i '/StreamMaxLength/c\StreamMaxLength 25M' /etc/clamav/clamd.conf
			service clamav-freshclam start
			service clamav-daemon start
			;;
		spamassassin)
			sed -i '/rewrite_header/c\rewrite_header Subject [SPAM]' /etc/spamassassin/local.cf
			sed -i '/report_safe/c\report_safe 2' /etc/spamassassin/local.cf
			sed -i '/^OPTIONS=/s/=.*/="--create-prefs --max-children 5 --helper-home-dir --username debian-spamd --socketpath \/var\/run\/spamd.sock --socketowner debian-spamd --socketgroup debian-spamd"/' /etc/default/spamassassin
			sed -i '/^CRON=/s/=.*/="1"/' /etc/default/spamassassin
			sed -i '/^ENABLED=/s/=.*/="1"/' /etc/default/spamassassin
			;;
		webserver)
			rm -rf /etc/php5/fpm/pool.d/* 2> /dev/null
			rm -rf /etc/nginx/{sites-available,sites-enabled}/* 2> /dev/null
			cp nginx/conf/sites-available/mail /etc/nginx/sites-available/mail
			ln -s /etc/nginx/sites-available/mail /etc/nginx/sites-enabled/mail
			cp php5-fpm/conf/pool/mail.conf /etc/php5/fpm/pool.d/mail.conf
            cp php5-fpm/conf/php-fpm.conf /etc/php5/fpm/php-fpm.conf
            cp nginx/conf/nginx.conf /etc/nginx/nginx.conf
			chown -R www-data:www-data /var/lib/php5/
			sed -i "/date.timezone/c\php_admin_value[date.timezone] = $sys_timezone" /etc/php5/fpm/pool.d/mail.conf
			sed -i "/worker_processes/c\worker_processes $(($(grep ^processor /proc/cpuinfo | wc -l) *2));" /etc/nginx/nginx.conf
			;;
		postfixadmin)
			rm -rf /usr/share/nginx/mail 2> /dev/null
			mkdir -p /usr/share/nginx/mail/pfadmin
			cp nginx/conf/htdocs/index.php /usr/share/nginx/mail/
            cp nginx/conf/htdocs/robots.txt /usr/share/nginx/mail/
            cp nginx/conf/htdocs/autoconfig.xml /usr/share/nginx/mail/
            sed -i "s/fufix_sub/$sys_hostname/g" /usr/share/nginx/mail/autoconfig.xml
			tar xf pfadmin/inst/$postfixadmin_revision.tar -C pfadmin/inst/
			mv pfadmin/inst/$postfixadmin_revision/* /usr/share/nginx/mail/pfadmin/
			cp pfadmin/conf/config.local.php /usr/share/nginx/mail/pfadmin/config.local.php
			sed -i "s/my_postfixpass/$my_postfixpass/g" /usr/share/nginx/mail/pfadmin/config.local.php
			sed -i "s/my_postfixuser/$my_postfixuser/g" /usr/share/nginx/mail/pfadmin/config.local.php
			sed -i "s/my_postfixdb/$my_postfixdb/g" /usr/share/nginx/mail/pfadmin/config.local.php
			sed -i "s/domain.tld/$sys_domain/g" /usr/share/nginx/mail/pfadmin/config.local.php
			sed -i "s/change-this-to-your.domain.tld/$sys_domain/g" /usr/share/nginx/mail/pfadmin/config.inc.php
			chown -R www-data: /usr/share/nginx/
			rm -rf pfadmin/inst/$postfixadmin_revision
			;;
        roundcube)
            mkdir -p /usr/share/nginx/mail/rc
            tar xf roundcube/inst/$roundcube_version.tar -C roundcube/inst/
            mv roundcube/inst/$roundcube_version/* /usr/share/nginx/mail/rc/
            cp -R roundcube/conf/* /usr/share/nginx/mail/rc/
            sed -i "s/my_postfixuser/$my_postfixuser/g" /usr/share/nginx/mail/rc/plugins/password/config.inc.php
            sed -i "s/my_postfixpass/$my_postfixpass/g" /usr/share/nginx/mail/rc/plugins/password/config.inc.php
            sed -i "s/my_postfixdb/$my_postfixdb/g" /usr/share/nginx/mail/rc/plugins/password/config.inc.php
			sed -i "s/my_rcuser/$my_rcuser/g" /usr/share/nginx/mail/rc/config/config.inc.php
			sed -i "s/my_rcpass/$my_rcpass/g" /usr/share/nginx/mail/rc/config/config.inc.php
			sed -i "s/my_rcdb/$my_rcdb/g" /usr/share/nginx/mail/rc/config/config.inc.php
			conf_rcdeskey=$(genpasswd)
			sed -i "s/conf_rcdeskey/$conf_rcdeskey/g" /usr/share/nginx/mail/rc/config/config.inc.php
            chown -R www-data: /usr/share/nginx/
            mysql -u $my_rcuser -p$my_rcpass $my_rcdb < /usr/share/nginx/mail/rc/SQL/mysql.initial.sql
			rm -rf roundcube/inst/$roundcube_version
            rm -rf /usr/share/nginx/mail/rc/installer/
            ;;
		fail2ban)
			tar xf fail2ban/inst/$fail2ban_version.tar -C fail2ban/inst/
			rm -rf /etc/fail2ban/ 2> /dev/null
			(cd fail2ban/inst/$fail2ban_version ; python setup.py -q install 2> /dev/null)
			cp fail2ban/conf/fail2ban.init /etc/init.d/fail2ban
			cp fail2ban/conf/jail.local /etc/fail2ban/jail.local
			chmod +x /etc/init.d/fail2ban
			update-rc.d fail2ban defaults
			rm -rf fail2ban/inst/$fail2ban_version
			;;
		rsyslogd)
			sed "s/*.*;auth,authpriv.none/*.*;auth,mail.none,authpriv.none/" -i /etc/rsyslog.conf
			;;
		restartservices)
			cat /dev/null > /var/log/mail.err
			cat /dev/null > /var/log/mail.warn
			cat /dev/null > /var/log/mail.log
			cat /dev/null > /var/log/mail.info
			for var in fail2ban rsyslog nginx php5-fpm clamav-daemon clamav-freshclam spamassassin fuglu mysql dovecot postfix
			do
				service $var stop
				sleep 1.5
				service $var start
			done
			;;
		checkdns)
			if [[ -z $(dig -x $getpublicipv4 @8.8.8.8 | grep -i $sys_domain) ]]; then
				echo "$(yellowb WARNING): Remember to setup a PTR record: $getpublicipv4 does not point to $sys_domain (checked by Google DNS)"
			fi
			if [[ -z $(dig $sys_hostname.$sys_domain @8.8.8.8 | grep -i $getpublicipv4) ]]; then
				echo "$(yellowb WARNING): Remember to setup an A record for $sys_hostname.$sys_domain pointing to $getpublicipv4 (checked by Google DNS)"
			fi
			if [[ -z $(dig $sys_domain txt @8.8.8.8 | grep -i spf) ]]; then
				echo "$(textb HINT): You may want to setup a TXT record for SPF, see spfwizard.com for further information (checked by Google DNS)"
			fi
			;;
		setupsuperadmin)
			wget --quiet --no-check-certificate -O /dev/null https://localhost/pfadmin/setup.php
			php /usr/share/nginx/mail/pfadmin/scripts/postfixadmin-cli.php admin add $pfadmin_adminuser --password $pfadmin_adminpass --password2 $pfadmin_adminpass --superadmin
			;;
	esac
}