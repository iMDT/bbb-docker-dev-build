FROM ubuntu:22.04
LABEL authors="Fred Dixon, Anton Georgiev"

#Force rebuild - 26.11.2021 

ENV DEBIAN_FRONTEND noninteractive
ENV container docker

RUN update-locale LANG=en_US.UTF-8

RUN apt-get update && apt-get install -y \
  apt-transport-https        \
  apt-utils                  \
  ca-certificates            \
  curl                       \
  haveged                    \
  htop                       \
  iputils-ping               \
  language-pack-en           \
  net-tools                  \
  software-properties-common \
  strace                     \
  sudo                       \
  tcpdump                    \
  telnet                     \
  vim                        \
  wget                       \
  && apt-get clean           \
  && rm -rf /var/lib/apt/lists/*

# -- Anticipate docker user and group creation (for ubuntu 22 docker-in-docker compatibility)
RUN groupadd -o -g 999 docker

# -- Install yq 
RUN LC_CTYPE=C.UTF-8 add-apt-repository ppa:rmescandon/yq && \
  apt-get update &&          \
  apt-get install yq -y      \
  && apt-get clean           \
  && rm -rf /var/lib/apt/lists/*

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
RUN wget https://raw.githubusercontent.com/bigbluebutton/bbb-install/v2.8.x-release/bbb-install.sh -O- | sed 's|https://\$PACKAGE_REPOSITORY|http://\$PACKAGE_REPOSITORY|g' > /opt/docker-bbb/bbb-install.sh

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
