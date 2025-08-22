#!/usr/bin/env bash
set -e


fail () { echo $1 >&2; exit 1; }
if [[ $(id -u) -ne 0 ]] || [[ -z $SUDO_USER ]]; then
    fail "Please run 'sudo $0'"
fi
if [[ $(grep -i Microsoft /proc/version) ]]; then
    fail "Running on WSL, try running 'sudo ./ubuntu-wsl.sh'"
fi

[[ -z $NEWHOST ]] && read -e -p "Enter hostname to set: " NEWHOST
[[ $NEWHOST = *.*.* ]] || fail "hostname must contain two '.'s"
hostname $NEWHOST
echo $NEWHOST > /etc/hostname
grep -q $NEWHOST /etc/hosts || echo "127.0.0.1 $NEWHOST" >> /etc/hosts

[[ -z $EMAIL ]] && read -e -p "Enter your email address: " EMAIL

echo 'Defaults        timestamp_timeout=3600' >> /etc/sudoers

[[ -z $AUTO_REBOOT ]] && read -e -p "Reboot automatically when required for upgrades? [y/n] " -i y AUTO_REBOOT

myhome=/home/$SUDO_USER

mkdir /root/.gnupg
chmod 700 /root/.gnupg/
gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/apt-fast-keyring.gpg --keyserver keyserver.ubuntu.com --recv-keys 1EE2FF37CA8DA16B
chmod go+r /usr/share/keyrings/apt-fast-keyring.gpg
CODENAME=$(lsb_release -cs)
echo "deb [signed-by=/usr/share/keyrings/apt-fast-keyring.gpg] http://ppa.launchpad.net/apt-fast/stable/ubuntu $CODENAME main" | sudo tee /etc/apt/sources.list.d/apt-fast.list
cat >> /etc/apt/sources.list << EOF
deb http://ppa.launchpad.net/apt-fast/stable/ubuntu $CODENAME main
EOF
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1EE2FF37CA8DA16B
apt-get -qy install curl
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
apt-get update

export DEBIAN_FRONTEND=noninteractive
apt-get -qy install apt-fast
cp logrotate.conf apt-fast.conf /etc/
cp journald.conf /etc/systemd/
cp 50unattended-upgrades 10periodic /etc/apt/apt.conf.d/
cat >> /etc/apt/apt.conf.d/50unattended << EOF
Unattended-Upgrade::Mail "$EMAIL";
EOF
[[ $AUTO_REBOOT = y* ]] && echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> /etc/apt/apt.conf.d/50unattended

chown root:root /etc/{logrotate,apt-fast}.conf /etc/systemd/journald.conf /etc/apt/apt.conf.d/{50unattended-upgrades,10periodic}

env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=mail apt-fast full-upgrade -qy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'
sudo apt -qy autoremove

mkdir -p $myhome/.ssh
chmod 700 $myhome/.ssh
cat << 'EOF' >> $myhome/.ssh/config
Host *
  ServerAliveInterval 60
  StrictHostKeyChecking no

Host github.com
  User git
  Port 22
  Hostname github.com
  TCPKeepAlive yes
  IdentitiesOnly yes
EOF
chmod 600 $myhome/.ssh/config
chown -R $SUDO_USER:$SUDO_USER $myhome/.ssh


# This is often used to setup passwordless sudo; so disable it
#rm -f /etc/sudoers.d/90-cloud-init-users


# Enable firewall and allow ssh
ufw default deny incoming
ufw default allow outgoing
ufw allow 2222
ufw --force enable

echo 'We need to reboot your machine to ensure kernel upgrades are installed'
echo 'First, make sure you can login in a new terminal, and that you can run `sudo -i`.'
echo "Open a new terminal, and login as $SUDO_USER"
[[ -z $REBOOT ]] && read -e -p 'When you have confirmed you can login and run `sudo -i`, type "y" to reboot. ' REBOOT
[[ $REBOOT = y* ]] && shutdown -r now || echo You chose not to reboot now. When ready, type: shutdown -r now