#!/bin/bash

yum install -y --nogpgcheck https://s3.amazonaws.com/archive.zfsonlinux.org/epel/zfs-release.el7.noarch.rpm
yum install -y --nogpgcheck https://s3.amazonaws.com/clusterhq-archive/centos/clusterhq-release$(rpm -E %dist).noarch.rpm
yum install -y clusterhq-flocker-node
# Device mapper Base isnt exported with old version, need to update.
yum update -y device-mapper-libs

if selinuxenabled; then setenforce 0; fi
test -e /etc/selinux/config && sed --in-place='.preflocker' 's/^SELINUX=.*$/SELINUX=disabled/g' /etc/selinux/config

cd /opt/flocker
git clone https://github.com/swevm/scaleio-py.git
cd scaleio-py
python setup.py install

SIO_PLUGIN="https://github.com/emccorp/scaleio-flocker-driver"
PLUGIN_SRC_DIR="/opt/flocker/scaleio-flocker-driver"

# Comment out until public
git clone $PLUGIN_SRC $PLUGIN_SRC_DIR

# Install ScaleIO Driver
cd /opt/flocker/scaleio-flocker-driver
python setup.py install

# scaleio-py might install 2.5.1, flocker can't use over 2.5.0
pip uninstall 'requests==2.5.1'
pip install 'requests==2.4.3'

mkdir -p /var/opt/flocker
truncate --size 10G /var/opt/flocker/pool-vdev
zpool create flocker /var/opt/flocker/pool-vdev

# You still need to create node certs and API
# user certs manually.
# 4  flocker-ca create-node-certificate
# 5  cp 132ebcea-b19b-4452-8e4d-b59754a56c63.crt /etc/flocker/node.crt
# 6  cp 132ebcea-b19b-4452-8e4d-b59754a56c63.key /etc/flocker/node.key
# 7  flocker-ca create-api-certificate user
cd /etc/flocker/
if [ "$HOSTNAME" = tb.scaleio.local ]; then
    printf '%s\n' "on the tb host"
    flocker-ca initialize mycluster
    flocker-ca create-control-certificate tb.scaleio.local
    cp control-tb.scaleio.local.crt /etc/flocker/control-service.crt
    cp control-tb.scaleio.local.key /etc/flocker/control-service.key
    cp cluster.crt /etc/flocker/cluster.crt
    chmod 0600 /etc/flocker/control-service.key
fi

# Create Node Certs
flocker-ca create-node-certificate
ls -1 . | egrep '[A-Za-z0-9]*?-[A-Za-z0-9]*?-[A-Za-z0-9]*?-[A-Za-z0-9]*?-[A-Za-z0-9]*?.crt' | tr -d '\n' | xargs -0 -I file cp file /etc/flocker/node.crt
ls -1 . | egrep '[A-Za-z0-9]*?-[A-Za-z0-9]*?-[A-Za-z0-9]*?-[A-Za-z0-9]*?-[A-Za-z0-9]*?.key' | tr -d '\n' | xargs -0 -I file cp file /etc/flocker/node.key

# Create user certs
flocker-ca create-api-certificate user

# Flocker ports need to be open
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --add-icmp-block=echo-request 
firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -j ACCEPT
firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -j ACCEPT
# Docker port
firewall-cmd --permanent --zone=public --add-port=4243/tcp
# ScaleIO ports needs to be open
firewall-cmd --permanent --zone=public --add-port=6611/tcp
firewall-cmd --permanent --zone=public --add-port=9011/tcp
firewall-cmd --permanent --zone=public --add-port=7072/tcp
firewall-cmd --permanent --zone=public --add-port=443/tcp
firewall-cmd --permanent --zone=public --add-port=22/tcp
firewall-cmd --reload

# Docker needs to reload iptables after this.
enable docker.service
service docker restart

# Add insecure private key for access
mkdir /root/.ssh
touch /root/.ssh/authorized_keys
echo "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key" > /root/.ssh/authorized_keys
