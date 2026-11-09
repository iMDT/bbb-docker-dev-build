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

./bbb-install.sh -d -s "`hostname -f`" -v noble-41-dev

# Install the 4 extra playback format packages (presentation is already installed by bbb-install).
# Installed here (image build time, apt is healthy) so every container is born with all 5 formats
# available. NOT activated in recording.yml - activation is opt-in by whoever needs it
# (processing 5 formats costs minutes of CPU per recording; default stays presentation-only).
apt install -y bbb-playback-notes bbb-playback-screenshare bbb-playback-podcast bbb-playback-video

sed -i 's/::/0.0.0.0/g' /opt/freeswitch/etc/freeswitch/autoload_configs/event_socket.conf.xml

# Change the nginx lines
#sudo sed -i '22 s/# proxy_pass/proxy_pass/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
#sudo sed -i '23 s/proxy_pass/# proxy_pass/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
# Disable IPv6 localhost listens (nginx can't start with it)
sudo sed -e '/\[::1\]/ s/^#*/#/' -i /etc/nginx/sites-available/bigbluebutton

#Set NODE_TLS_REJECT_UNAUTHORIZED to make node allow image from self-signed certificate
#echo "NODE_TLS_REJECT_UNAUTHORIZED=0" | sudo tee -a /usr/share/meteor/bundle/bbb-html5-with-roles.conf
echo "NODE_TLS_REJECT_UNAUTHORIZED=0" | sudo tee -a /etc/environment

#Switch NginX static resource requests to Meteor
#sudo sed -i '/^location \/html5client\/locales/,+2 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '/^location \/html5client\/compatibility/,+3 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '/^location \/html5client\/resources/,+2 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '/^location \/html5client\/svgs/,+2 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '/^location \/html5client\/fonts/,+2 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx
sudo sed -i '/^location \/html5client\/__meteor__\/dynamic-import\/fetch/,+11 s/^/#/' /usr/share/bigbluebutton/nginx/bbb-html5.nginx

#html5: create config
sudo touch /etc/bigbluebutton/bbb-html5.yml;

#html5: set audio via http
sudo yq-go e -i '.public.media.sipjsHackViaWs = true' /etc/bigbluebutton/bbb-html5.yml

#Enable Hasura console and set password to 'bigbluebutton'
echo "HASURA_GRAPHQL_ENABLE_CONSOLE=true" | sudo tee -a /etc/bigbluebutton/bbb-graphql-server.env
sudo sed -i 's/HASURA_GRAPHQL_ADMIN_SECRET=.*/HASURA_GRAPHQL_ADMIN_SECRET=bigbluebutton/g' /etc/default/bbb-graphql-server-admin-pass
sudo yq-go e -i ".admin_secret = \"bigbluebutton\"" /usr/share/bbb-graphql-server/config.yaml

#Set graphql database password to 'bbb_graphql'
until sudo runuser -u postgres -- psql -c "SELECT 1" > /dev/null 2>&1; do
    echo "Waiting for Postgres to be ready..."
    sleep 1
done
echo "PostgreSQL is ready."
sudo runuser -u postgres -- psql -c "ALTER USER postgres PASSWORD 'bbb_graphql'"



mkdir /home/bigbluebutton/
chown bigbluebutton /home/bigbluebutton/ -R

# Restart
bbb-conf --restart

# Disable auto start (unnecessary services)
#find /etc/systemd/ | grep wants | grep -v bigbluebutton | xargs -r -n 1 basename | grep service | grep -v networking | grep -v networking | grep -v syslog | grep -v tty   | xargs -r -n 1 -I __ systemctl disable __
# `|| true` so a unit that doesn't exist on this release (e.g. ondemand, removed after Ubuntu 22.04) doesn't abort the script under `set -e`
sudo systemctl disable e2scrub_reap haveged systemd-pstore systemd-timesyncd apparmor networkd-dispatcher systemd-resolved unattended-upgrades dmesg rsync || true

# Enable bbb services (that is not being enabled properly during bbb-install
# Enabled already: bbb-apps-akka bbb-fsesl-akka bbb-rap-caption-inbox bbb-rap-resque-worker bbb-rap-starter
# Enable one by one so a unit that doesn't exist on this release (e.g. bbb-pads/etherpad replaced by bbb-shared-notes-server in 4.0) doesn't abort the script under `set -e`
for svc in bbb-export-annotations bbb-pads bbb-web bbb-webrtc-sfu etherpad bbb-shared-notes-server freeswitch bbb-graphql-server bbb-graphql-middleware bbb-graphql-actions; do
  sudo systemctl enable "$svc" || echo "Unit $svc does not exist, skipping"
done

# After starting bbb-graphql-server we can configure Hasura
sudo systemctl daemon-reload
sudo systemctl start bbb-graphql-actions.service || echo "bbb-graphql-actions service could not be registered or started"
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

apt-get install -y git-core

# Install api-mate to run locally
sudo mkdir /usr/share/api-mate
sudo git clone -b gh-pages --single-branch https://github.com/mconf/api-mate.git /usr/share/api-mate/


# Install Sipp for dial-in tests
apt install -y pkg-config dh-autoreconf ncurses-dev build-essential libssl-dev libpcap-dev libncurses5-dev libsctp-dev lksctp-tools cmake
git clone --recurse-submodules https://github.com/SIPp/sipp.git /opt/sipp
cd /opt/sipp
git checkout 4682fdba2b63007f13a632c6eb06f0ece84cb7df #Set an old commit as the current code is not working
cmake . -DUSE_SSL=1 -DUSE_SCTP=1 -DUSE_PCAP=1 -DUSE_GSL=1
make
sudo make install
cd /
echo "SIPp is installed: removing its build tree (keeping /opt/sipp/pcap, which 'sipp -sn uac_pcap' plays) and the packages only its build needed"
find /opt/sipp -mindepth 1 -maxdepth 1 ! -name pcap -exec rm -rf {} +
apt-get purge -y cmake dh-autoreconf libpcap-dev libsctp-dev libncurses-dev

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

# sbt launcher from the sbt release, pinned and checksummed. bbb-web builds with ./gradlew and
# nothing uses grails or maven, so this is the only build tool installed by hand; the launcher
# fetches the sbt version each project pins into the mounted ~/.ivy2. The tarball also carries
# native clients for macOS, aarch64 and Windows (118 MB); only the Linux x86_64 one stays.
SBT_VERSION=1.10.7
SBT_SHA256=32c15233c636c233ee25a2c31879049db7021cfef70807c187515c39b96b0fe6
curl -fsSL -o /tmp/sbt.tgz "https://github.com/sbt/sbt/releases/download/v${SBT_VERSION}/sbt-${SBT_VERSION}.tgz"
echo "${SBT_SHA256}  /tmp/sbt.tgz" | sha256sum -c
tar -xzf /tmp/sbt.tgz -C /opt
rm /tmp/sbt.tgz
find /opt/sbt/bin -name 'sbtn-*' ! -name 'sbtn-x86_64-pc-linux' -delete

su bigbluebutton -c bash -l << 'EOF'
    # A failed step here must fail the build instead of publishing an image without the tool
    set -e

    echo "export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64" >> ~/.profile
    echo 'export PATH="/opt/sbt/bin:$PATH"' >> ~/.profile
    source ~/.profile
    sbt --script-version

    mkdir -p ~/.sbt/1.0
    echo '
        resolvers += "Artima Maven Repository" at "https://repo.artima.com/releases"
        updateOptions := updateOptions.value.withCachedResolution(true)
    ' > $HOME/.sbt/1.0/global.sbt

    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    echo 'export PATH="/opt/sbt/bin:$PATH"' >> $HOME/.zshrc

    # Create sbt/maven/gradle/npm directories to set bigbluebutton as owner
    mkdir -p $HOME/.ivy2
    mkdir -p $HOME/.m2
    mkdir -p $HOME/.cache
    mkdir -p $HOME/.gradle
    mkdir -p $HOME/.npm

    # Build source artifacts ( to have dependencies cached )
    # The lines bellow is commented since the container will mount the cache dirs of its host
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

# Install build tools for bbb-graphql-middleware
# The version bbb-graphql-middleware's go.mod asks for; an older toolchain makes every fresh
# container download the right one into the unpersisted home on the first "go run".
GO_VERSION=1.27.3
sudo wget --no-verbose https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
sudo rm -rf go${GO_VERSION}.linux-amd64.tar.gz /usr/local/go/test /usr/local/go/doc /usr/local/go/misc /usr/local/go/api
sudo ln -sf /usr/local/go/bin/go /usr/bin/go


# Install percona/pg_stat_monitor for Postgresql query performance monitoring
# Detect the installed PostgreSQL major version (noble ships 16) so the build
# and config paths don't stay pinned to an old release like 3.0.x's hardcoded 14.
# libkrb5-dev is required to provide gssapi.h when compiling pg_stat_monitor.
PG_VERSION="$(ls /etc/postgresql/ | sort -V | tail -n1)"
sudo apt install -y build-essential postgresql-server-dev-${PG_VERSION} libkrb5-dev
git clone https://github.com/percona/pg_stat_monitor.git /tmp/pg_stat_monitor
cd /tmp/pg_stat_monitor
make USE_PGXS=1
sudo make USE_PGXS=1 install
cd /
rm -rf /tmp/pg_stat_monitor
# postgresql-server-dev pulls the LLVM and clang development packages (about 650 MB); only the
# built extension is needed from here on. clang-17 and llvm-17-dev are named because dpkg-dev
# (build-essential) recommends a C compiler and clang would otherwise be kept to satisfy it.
sudo apt-get purge -y --autoremove postgresql-server-dev-${PG_VERSION} libkrb5-dev clang-17 llvm-17-dev
sudo sed -i "s/#shared_preload_libraries = ''/shared_preload_libraries = 'pg_stat_monitor'/g" /etc/postgresql/${PG_VERSION}/main/postgresql.conf


# Update files
sudo apt-get -y install plocate
sudo updatedb

# Clear docker: the container talks to the host's daemon through /docker.sock, so the daemon,
# containerd and the plugins installed by bbb-install go, only the CLI stays. The image data the
# inner daemon wrote during the install (the bbb-soffice image) lives under /var/lib/containerd
# as well as /var/lib/docker.
sudo systemctl stop docker.socket docker containerd || true
sudo apt-get purge -y docker-ce docker-ce-rootless-extras containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/containerd
sudo find /var/lib/docker -mindepth 1 -maxdepth 1 -exec rm -rf {} +   # a volume mount in the build container, so not removable itself
echo "DOCKER_HOST=unix:///docker.sock" | sudo tee -a /etc/environment

# Avoid deleting /tmp files on boot (because now container mounts the host /tmp)
# Disable /tmp cleaner
sudo sed -e '/\/tmp/ s/^#*/#/' -i /usr/lib/tmpfiles.d/tmp.conf

# What the install run leaves behind: apt lists (recreated by apt update), the download cache,
# the journal and logs of the install. (~/.cache and ~/.npm are host volumes at run time.)
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo journalctl --rotate && sudo journalctl --vacuum-time=1s
sudo find /var/log -type f -name '*.gz' -delete
# -c: with fs.protected_regular, root cannot do a creating open on another user's file in a sticky directory
sudo find /var/log -type f \( -name '*.log' -o -name '*.log.*' -o -name 'syslog*' \) -exec truncate -c -s 0 {} +
sudo rm -rf /root/.cache /root/.npm
sudo updatedb

echo "BBB configuration completed."
exit 0;
