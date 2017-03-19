#!/usr/bin/env /bin/sh

################################################################################
                              #   CONFIGS   #
                              # # # # # # # #

################################################################################
ROOT_USER_ALTERNATIVE="superuser"
SSH_PORT=4422
LANG_SET="en_US.UTF-8"

SSHD_CONFIG="/etc/ssh/sshd_config"





###############################################################################
                              #  GROUNDWORK #
                              # # # # # # # #

### 1. go into root mode: 'su root' or'sudo -i'
### 2. make sure, the root user has a password and you know it. if not: 'passwd'
################################################################################





################################################################################
### first5min on server script code
################################################################################


# running as root or not
if [ $(id -u) -eq 0 ]; then
    echo "(1) change root pw (unset on fresh ubuntu instances)"
    passwd

    export LANGUAGE=${LANG_SET}
    export LANG=${LANG_SET}
    export LC_ALL=${LANG_SET}
    export LC_CTYPE=${LANG_SET}
    locale-gen ${LANG_SET}
else
    echo "TODO: switch to root and try to run this script again (-> aborted)"
    exit 1
    #echo "(1) switching to root (TODO: and setting password)"
    # sudo su
    #su root
    #sudo -i
fi



# 2. creating new users (superuser and a custom one)
echo "(2) create new users"
echo "==> ${ROOT_USER_ALTERNATIVE}: "
adduser "${ROOT_USER_ALTERNATIVE}" --shell /bin/bash --gecos ""
echo "" >> /home/${ROOT_USER_ALTERNATIVE}/.profile
echo "LANGUAGE=${LANG_SET}" >> /home/${ROOT_USER_ALTERNATIVE}/.profile
echo "LANG=${LANG_SET}" >> /home/${ROOT_USER_ALTERNATIVE}/.profile
echo "LC_ALL=${LANG_SET}" >> /home/${ROOT_USER_ALTERNATIVE}/.profile
echo "LC_CTYPE=${LANG_SET}" >> /home/${ROOT_USER_ALTERNATIVE}/.profile

read -p "==> Whats the name of your custom user? " custom_user
if [ -z "${custom_user}" ]; then
    read -p "Thats not a valid user name! last chance: " custom_user
fi

if [ ! -z "${custom_user}" ]; then
    adduser ${custom_user} --shell /bin/bash --disabled-password --gecos ""
else
    echo "Wrong input. Script will terminate immediatlly"
    exit 0
fi
[ -d /home/${custom_user}/.ssh ] || mkdir /home/${custom_user}/.ssh
ssh-keygen -q -t rsa -b 4096 -N "" -C "${custom_user}@localhost" -f "/home/${custom_user}/.ssh/id_rsa"
chmod 700 /home/${custom_user}/.ssh
chown ${custom_user}:${custom_user} /home/${custom_user} -R


# 3. creating new admin group
echo "(3a) create new group ('admins')"
groupadd admins
echo "(3b) and adding '${ROOT_USER_ALTERNATIVE}' to it"
usermod -a -G admins,adm,sudo,cdrom,dip,www-data,plugdev,lpadmin,sambashare ${ROOT_USER_ALTERNATIVE}
echo "...superuser is now member of: `groups`"


# 4. add superuser to sudoers
echo "(4) add ${ROOT_USER_ALTERNATIVE} to sudoers and admins group"
echo "" >> /etc/sudoers
echo "# added by admin" >> /etc/sudoers
echo "${ROOT_USER_ALTERNATIVE} ALL=(ALL) ALL" >> /etc/sudoers


# 5. adding public ssh keys to authorized_keys of superuser
echo "(5) add your public key to ${ROOT_USER_ALTERNATIVE} s authorized_keys -file"
[ -d /home/${ROOT_USER_ALTERNATIVE}/ ] || mkdir /home/${ROOT_USER_ALTERNATIVE}/
[ -d /home/${ROOT_USER_ALTERNATIVE}/.ssh ] || mkdir /home/${ROOT_USER_ALTERNATIVE}/.ssh
[ -e /home/${ROOT_USER_ALTERNATIVE}/.ssh/authorized_keys ] || touch /home/${ROOT_USER_ALTERNATIVE}/.ssh/authorized_keys
read -p "c/p your public key in here ==> " pub_key
if [ -z "${pub_key}" ]; then
    echo "its no valid input. adding aborted. please append your key manually into '/home/${ROOT_USER_ALTERNATIVE}/.ssh/authorized_keys' after this script"
else
    echo ${pub_key} >> /home/${ROOT_USER_ALTERNATIVE}/.ssh/authorized_keys
fi
chmod 700 /home/${ROOT_USER_ALTERNATIVE}/.ssh
chmod 600 /home/${ROOT_USER_ALTERNATIVE}/.ssh/authorized_keys
chown ${ROOT_USER_ALTERNATIVE}:${ROOT_USER_ALTERNATIVE} /home/${ROOT_USER_ALTERNATIVE} -R



# 6. securing some stuff
echo "(6) securing ssh and stuff"
echo "...re-configure ssh (edit sshd_config)"

cp ${SSHD_CONFIG} ${SSHD_CONFIG}.default

sed -r "s/^#?\s?PermitRootLogin .*/PermitRootLogin no/i" -i ${SSHD_CONFIG}
sed -r "s/^#?\s?Port .*/Port ${SSH_PORT}/i" -i ${SSHD_CONFIG}

sshConfigProperty="AllowUsers";
grep -q "${sshConfigProperty}" ${SSHD_CONFIG}
if [ $? -eq 0 ]; then # FOUND
    sed "s/^.*${sshConfigProperty}.*/AllowUsers ${ROOT_USER_ALTERNATIVE}/i" -i ${SSHD_CONFIG}
else
    echo "" >> ${SSHD_CONFIG}
    echo "AllowUsers ${ROOT_USER_ALTERNATIVE}" >> ${SSHD_CONFIG}
fi


if [ ! -z "${pub_key}" ]; then
    sshConfigProperty="PasswordAuthentication";

    grep -q "${sshConfigProperty}" ${SSHD_CONFIG}
    if [ $? -eq 0 ]; then # FOUND
        sed -i -E -e "s/^#?${sshConfigProperty} (no|yes){1}$/PasswordAuthentication no/g" ${SSHD_CONFIG}
    else
        echo "" >> ${SSHD_CONFIG}
        echo "PasswordAuthentication no" >> ${SSHD_CONFIG}
    fi
fi

echo "
# keep alive 1 hour
ClientAliveInterval 120
ClientAliveCountMax 30" >> ${SSHD_CONFIG}


echo "...reload ssh changed configs"
/etc/init.d/ssh reload
echo "...restricting 'su'-command"
dpkg-statoverride --update --add root admins 4750 /bin/su


# 7. updating the operating system
echo "(7) update the OS [currently ubuntu]"
apt-get update
apt-get upgrade -y


# 8. enable auto security updates
echo "(8) update mechanisms"
echo "Q: enable security updates? [y,N] "
read -p " [y] " enableSecurityUpdates
enableSecurityUpdates=${enableSecurityUpdates:-"y"}
if [ "${enableSecurityUpdates}" = "y" ]; then
    apt-get install unattended-upgrades -y
    dpkg-reconfigure --priority=low unattended-upgrades
fi


# 8. install some important packages
echo "(9) installing some important packages"
apt-get install -y git-core


# 9. configure language encoding
echo "(10) configure language encoding"
locale-gen UTF-8


# 9. setting some defaults on the firewall
command -v ufw >/dev/null 2>&1 || apt-get -y install ufw
echo "(11) initial firewall configurations and enableing"
ufw status | grep inactive &> /dev/null
if [ $? = 0 ]; then
    echo "WARNING: ufw is not enabled."
else
    echo "...utw in enabled. everything is fine"
fi
sed "s/^ *IPV6 .*/IPV6=yes/i" -i /etc/default/ufw
ufw disable
ufw allow ${SSH_PORT}/tcp
echo "Q: open web ports (80,443)? [N,y]"
read -p " [y] " openWebPorts
openWebPorts=${openWebPorts:-"y"}
if [ "${openWebPorts}" = "y" ]; then
    ufw allow 80/tcp
    ufw allow 443/tcp
fi
ufw enable


echo "==> finishing up"
service ssh restart

echo "==> ...and we are DONE"
echo " "
echo " "
echo "################################################################################"
echo "                             #  NEXT  STEPS  #"
echo "                             # # # # # # # # #"
echo " "
echo " ===> eventually revisiting /etc/ssh/sshd_conf"
echo " ===> reconnect via ssh with ${ROOT_USER_ALTERNATIVE} to test, if everything"
echo "      is in place and works great"
echo " ===> install tools like logwatch, fail2ban, etc"
echo "################################################################################"


echo "(12) machine configurations"
echo "Q: change hostname ($(hostname))? [...,N] "
read -p " [N] " newHostname
changeHostname=${newHostname:-"N"}
if [ "${changeHostname}" != "N" ]; then
    echo ${changeHostname}"" > /etc/hostname
    # TODO: find and replace in/etc/hosts
fi


echo "(13) all done..."
echo "Q: Do you want to reboot the machine? [y,N] "
read -p " [y] " restartRequired
restartRequired=${restartRequired:-"y"}
if [ "${restartRequired}" = "y" ]; then
    reboot
fi

exit 0
