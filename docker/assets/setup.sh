#!/bin/bash

#
# BlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2018 BigBlueButton Inc.
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#
set -x

DEBIAN_FRONTEND=noninteractive

cd "$(dirname "$0")"

set -e

chmod 1777 /tmp/

#echo 'Acquire::http::Proxy "http://10.131.0.1:3128/";' > /etc/apt/apt.conf.d/proxy.conf
#echo 'Acquire::https::Proxy "http://10.131.0.1:3128/";' >> /etc/apt/apt.conf.d/proxy.conf

apt update 

set +e
apt install -y redis-server
sed -i 's/bind 127.0.0.1 ::1/bind 127.0.0.1/g'  /etc/redis/redis.conf
set -e
apt install -y redis-server

apt install -yq nginx
systemctl enable nginx
systemctl start nginx

./bbb-install.sh -d -s "`hostname -f`" -v bionic-24-dev -a
sed -i 's/::/0.0.0.0/g' /opt/freeswitch/etc/freeswitch/autoload_configs/event_socket.conf.xml

# Change the nginx lines
sudo sed -i '22 s/# proxy_pass/proxy_pass/' /etc/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '23 s/proxy_pass/# proxy_pass/' /etc/bigbluebutton/nginx/bbb-html5.nginx


mkdir /home/bigbluebutton/
chown bigbluebutton /home/bigbluebutton/ -R

# Restart
bbb-conf --restart

# Disable auto start 
find /etc/systemd/ | grep wants | xargs -r -n 1 basename | grep service | grep -v networking | grep -v tty   | xargs -r -n 1 -I __ systemctl disable __

# Install ssh server
apt install -y openssh-server

# Install zsh
apt install -y zsh


# Install build tools for java
apt remove -y 'openjdk-11-*'
apt-get install git-core ant ant-contrib openjdk-8-jdk-headless

su bigbluebutton -c bash -l << 'EOF'
    # Install build tools for html5
    curl https://install.meteor.com/ | sh

    echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> ~/.profile
    echo 'source "$HOME/.sdkman/bin/sdkman-init.sh"' >> ~/.profile 
    source ~/.profile

    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"

    sdk install gradle 5.5.1
    sdk install grails 3.3.9
    sdk install sbt 1.2.8
    sdk install maven 3.5.0

    mkdir -p ~/.sbt/1.0
    echo '
        resolvers += "Artima Maven Repository" at "http://repo.artima.com/releases"
        updateOptions := updateOptions.value.withCachedResolution(true)
    ' > $HOME/.sbt/1.0/global.sbt
    
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    
    echo '
         source "$HOME/.sdkman/bin/sdkman-init.sh"
    ' >> $HOME/.zshrc

    # Build source artifacts ( to have dependencies cached )
    cd ~
    git clone --single-branch --branch develop https://github.com/bigbluebutton/bigbluebutton.git
     
    cd bigbluebutton
     
    cd bbb-common-message/
    ./deploy.sh
    cd ..
     
    cd bbb-common-web/
    ./deploy.sh
    cd ..
     
    cd bigbluebutton-html5/
    npm install
    cd ..
    
    rm -rf ~/bigbluebutton/
EOF


# Update files
updatedb

# Clear docker
sudo systemctl stop docker.socket
sudo rm -rf /var/lib/docker

echo "BBB configuration completed.";
exit 0;
