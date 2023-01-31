FROM ubuntu:20.04
MAINTAINER ffdixon@bigbluebutton.org

#Force rebuild - 26.11.2021 

ENV DEBIAN_FRONTEND noninteractive
ENV container docker

RUN apt update 
RUN apt install -y wget apt-transport-https curl ca-certificates
RUN apt install -y language-pack-en
RUN update-locale LANG=en_US.UTF-8
RUN apt install -y --no-install-recommends apt-utils
RUN apt install -y wget software-properties-common
RUN apt install -y mlocate strace iputils-ping telnet tcpdump vim htop

# -- Install docker (for docker-in-docker)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list
RUN apt update
RUN apt install -y docker-ce
# (and ensure it will never see the light again)
RUN chmod 000 /usr/bin/dockerd
RUN chmod 000 /usr/bin/containerd
RUN rm /lib/systemd/system/docker.service

# -- Install yq 
# RUN LC_CTYPE=C.UTF-8 add-apt-repository ppa:rmescandon/yq
# RUN apt update
# RUN LC_CTYPE=C.UTF-8 apt install yq -y

RUN apt-get install -y \
  haveged    \
  net-tools  \
  sudo

# -- Modify systemd to be able to run inside container
RUN apt-get update \
    && apt-get install -y systemd

# -- Download missing keys
# RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 32A0A01CC64D2A34

# -- Disable unneeded services
RUN systemctl disable systemd-journal-flush
RUN systemctl disable systemd-update-utmp.service

# -- Finish startup 
#    Add a number there to force update files
ADD assets/nocache /root
RUN mkdir /opt/docker-bbb/
# RUN wget https://ubuntu.bigbluebutton.org/bbb-install-25.sh -O- | sed 's|https://\$PACKAGE_REPOSITORY|http://\$PACKAGE_REPOSITORY|g' > /opt/docker-bbb/bbb-install.sh
RUN wget https://ubuntu.bigbluebutton.org/bbb-install-2.6.sh -O- | sed 's|https://\$PACKAGE_REPOSITORY|http://\$PACKAGE_REPOSITORY|g' > /opt/docker-bbb/bbb-install.sh

RUN chmod 755 /opt/docker-bbb/bbb-install.sh
ADD ./assets/setup.sh /opt/docker-bbb/setup.sh
RUN chmod 700 /opt/docker-bbb/setup.sh


RUN useradd bigbluebutton --uid 1000 -s /bin/bash
RUN sh -c 'echo "bigbluebutton ALL=(ALL:ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/bigbluebutton'
RUN sh -c 'echo "bigbluebutton:bigbluebutton" | chpasswd'

ADD ./assets/rc.local /etc/
RUN chmod 755 /etc/rc.local

ADD ./assets/haveged.service /etc/systemd/system/default.target.wants/haveged.service

RUN printf '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d 

ENTRYPOINT ["/bin/systemd", "--system", "--unit=multi-user.target"]

