#!/bin/bash
echo " Starting setup.sh"

#
# BlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2023 BigBlueButton Inc.
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
sed -i 's/bind 127.0.0.1 ::1/bind 0.0.0.0/g'  /etc/redis/redis.conf
set -e

apt install -yq nginx
systemctl enable nginx
systemctl start nginx

sudo apt install -y rsyslog
# [ -f /etc/systemd/system/syslog.service ] || sudo ln -s /lib/systemd/system/rsyslog.service /etc/systemd/system/syslog.service

./bbb-install.sh -d -s "`hostname -f`" -v jammy-28-develop
sed -i 's/::/0.0.0.0/g' /opt/freeswitch/etc/freeswitch/autoload_configs/event_socket.conf.xml

# Change the nginx lines
sudo sed -i '22 s/# proxy_pass/proxy_pass/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '23 s/proxy_pass/# proxy_pass/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
# Disable IPv6 localhost listens (nginx can't start with it)
sudo sed -e '/\[::1\]/ s/^#*/#/' -i /etc/nginx/sites-available/bigbluebutton

#Set NODE_TLS_REJECT_UNAUTHORIZED to make node allow image from self-signed certificate
echo "NODE_TLS_REJECT_UNAUTHORIZED=0" | sudo tee -a /usr/share/meteor/bundle/bbb-html5-with-roles.conf
echo "NODE_TLS_REJECT_UNAUTHORIZED=0" | sudo tee -a /etc/environment

#Switch NginX static resource requests to Meteor
sudo sed -i '/^location \/html5client\/locales/,+2 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '/^location \/html5client\/compatibility/,+3 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '/^location \/html5client\/resources/,+2 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '/^location \/html5client\/svgs/,+2 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '/^location \/html5client\/fonts/,+2 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx

#html5: create config
sudo touch /etc/bigbluebutton/bbb-html5.yml;

#html5: set audio via http
sudo yq e -i '.public.media.sipjsHackViaWs = true' /usr/share/meteor/bundle/programs/server/assets/app/config/settings.yml
sudo yq e -i '.public.media.sipjsHackViaWs = true' /etc/bigbluebutton/bbb-html5.yml

#Enable Hasura console
sudo sed -i 's/HASURA_GRAPHQL_ENABLE_CONSOLE=false/HASURA_GRAPHQL_ENABLE_CONSOLE=true/g' /etc/default/bbb-graphql-server

mkdir /home/bigbluebutton/
chown bigbluebutton /home/bigbluebutton/ -R

# Restart
bbb-conf --restart

# Disable auto start (unnecessary services)
#find /etc/systemd/ | grep wants | grep -v bigbluebutton | xargs -r -n 1 basename | grep service | grep -v networking | grep -v networking | grep -v syslog | grep -v tty   | xargs -r -n 1 -I __ systemctl disable __
sudo systemctl disable e2scrub_reap haveged systemd-pstore systemd-timesyncd apparmor networkd-dispatcher systemd-resolved unattended-upgrades ondemand dmesg rsync

# Enable bbb services (that is not being enabled properly during bbb-install
# Enabled already: bbb-apps-akka bbb-fsesl-akka bbb-rap-caption-inbox bbb-rap-resque-worker bbb-rap-starter
sudo systemctl enable bbb-export-annotations bbb-html5 bbb-pads bbb-web bbb-webrtc-sfu disable-transparent-huge-pages etherpad freeswitch bbb-graphql-server bbb-graphql-middleware

# After starting bbb-graphql-server we can configure Hasura
sudo systemctl daemon-reload
sudo systemctl start bbb-graphql-server || echo "bbb-graphql-server service could not be registered or started"
# Apply BBB metadata in Hasura
cd /usr/share/bbb-graphql-server
hasura metadata apply
cd ..
#rm -rf /usr/share/bbb-graphql-server/metadata

# Install ssh server
apt install -y openssh-server

# Install zsh
apt install -y zsh

# Install build tools for record-and-playback
apt install -y ruby-dev libsystemd-dev

# Install build tools for java
apt-get install -y git-core ant ant-contrib openjdk-17-jdk-headless

# Install Sipp for dial-in tests
apt install -y pkg-config dh-autoreconf ncurses-dev build-essential libssl-dev libpcap-dev libncurses5-dev libsctp-dev lksctp-tools cmake
git clone --recurse-submodules https://github.com/SIPp/sipp.git /opt/sipp
cd /opt/sipp
cmake . -DUSE_SSL=1 -DUSE_SCTP=1 -DUSE_PCAP=1 -DUSE_GSL=1
make
sudo make install
rm -r /opt/sipp/gtest
rm -r /opt/sipp/src

# Set dial plan for internal calls
cat << EOF > "/opt/freeswitch/conf/dialplan/public/bbb_sip.xml"
<include>
    <extension name="bbb_sp_call" continue="true">
      <condition field="network_addr" expression="\${domain}" break="on-false">
        <action application="set" data="bbb_authorized=true"/>
        <action application="transfer" data="\${destination_number} XML default"/>
      </condition>
    </extension>
</include>
EOF

su bigbluebutton -c bash -l << 'EOF'
    # Install build tools for html5
    #curl https://install.meteor.com/ | sh
    #Force version 2.13 because it can't run 2.13.1 https://github.com/meteor/meteor/issues/12771
    curl https://install.meteor.com/ | sed 's/RELEASE="2.13.*"/RELEASE="2.13"/' | sh

    echo "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> ~/.profile
    echo 'source "$HOME/.sdkman/bin/sdkman-init.sh"' >> ~/.profile 
    source ~/.profile

    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"

    sdk install gradle 7.3.1
    sdk install grails 5.3.2
    sdk install sbt 1.6.2
    sdk install maven 3.5.0

    mkdir -p ~/.sbt/1.0
    echo '
        resolvers += "Artima Maven Repository" at "https://repo.artima.com/releases"
        updateOptions := updateOptions.value.withCachedResolution(true)
    ' > $HOME/.sbt/1.0/global.sbt
    
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    
    echo '
         source "$HOME/.sdkman/bin/sdkman-init.sh"
    ' >> $HOME/.zshrc

    # Create sbt directories to set bigbluebutton as owner
    mkdir $HOME/.ivy2
    mkdir $HOME/.m2
    mkdir $HOME/.gradle

    # Build source artifacts ( to have dependencies cached )
    #cd ~
    #git clone --single-branch --branch v3.0.x-release https://github.com/bigbluebutton/bigbluebutton.git
    #git clone --single-branch --branch develop https://github.com/bigbluebutton/bigbluebutton.git
    
    #cd bigbluebutton
     
    #cd bbb-common-message/
    #./deploy.sh
    #cd ..
     
    #cd bbb-common-web/
    #./deploy.sh
    #cd ..

    #cd bigbluebutton-web/
    #./build.sh </dev/null
    #cd ..
    
    #cd bigbluebutton-html5/
    #npm install
    #cd ..

    #rm -rf ~/bigbluebutton/
EOF


# Update files
sudo apt-get -y install plocate
sudo updatedb

# Clear docker
sudo systemctl stop docker.socket
sudo find /var/lib/docker/ -mindepth 1 -maxdepth 1 | xargs sudo rm -rf || true

# Uninstall docker daemon (as we use docker-ce)
sudo apt remove -y docker-ce
echo "DOCKER_HOST=unix:///docker.sock" | sudo tee -a /etc/environment

# Avoid deleting /tmp files on boot (because now container mounts the host /tmp)
# Disable /tmp cleaner
sudo sed -e '/\/tmp/ s/^#*/#/' -i /usr/lib/tmpfiles.d/tmp.conf

echo "BBB configuration completed."
exit 0;
