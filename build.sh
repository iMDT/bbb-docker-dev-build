#!/bin/bash
if [ "$EUID" -ne 0 ]; then
	echo "Please run this script as root ( or with sudo )" ;
	exit 1;
fi;

CERT_FULLCHAIN_URL="$1"
CERT_PRIVKEY_URL="$2"

DOCKER_CHECK=`docker --version &> /dev/null && echo 1 || echo 0`

if [ "$DOCKER_CHECK"  = "0" ]; then
	echo "Docker not found";
	apt update;
	apt install apt-transport-https ca-certificates curl software-properties-common
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
	apt update
	apt install docker-ce -y
	systemctl enable docker
	systemctl start docker
	systemctl status docker
else
	echo "Docker already installed";
fi

set -e

IMAGE_CHECK=`docker image inspect bbb_docker_build &> /dev/null && echo 1 || echo 0`
if [ "$IMAGE_CHECK"  = "1" ]; then
	docker image rm bbb_docker_build --force
fi;

date > docker/assets/nocache
echo "Docker image doesn't exists, building"
docker build -t bbb_docker_build docker/
echo "Docker image created"

if [ -d certs ]; then
	rm -rf certs
fi;

mkdir certs/
wget "$CERT_FULLCHAIN_URL" -O certs/fullchain.pem
wget "$CERT_PRIVKEY_URL" -O certs/privkey.pem

docker kill bbb_docker_build &> /dev/null || echo 
docker rm bbb_docker_build &> /dev/null || echo 
docker run -v`pwd`/certs/fullchain.pem:/etc/letsencrypt/live/bbb-docker-build.bbbvm.imdt.com.br/fullchain.pem -v`pwd`/certs/privkey.pem:/etc/letsencrypt/live/bbb-docker-build.bbbvm.imdt.com.br/privkey.pem -v/sys/fs/cgroup:/sys/fs/cgroup:ro -v docker_in_docker_build:/var/lib/docker --tmpfs /run --tmpfs /run/lock --tmpfs /tmp:exec,mode=1777 --privileged --cap-add NET_ADMIN --cap-add SYS_ADMIN -e container=docker --security-opt seccomp=unconfined  --name bbb_docker_build --hostname bbb-docker-build.bbbvm.imdt.com.br -d bbb_docker_build

docker exec -u root bbb_docker_build sh -c " /opt/docker-bbb/setup.sh || ( echo ERROR ; sleep 100000 ) "
docker exec -u root bbb_docker_build sh -c " rm /opt/docker-bbb/setup.sh "
docker exec -u root bbb_docker_build sh -c " halt "

echo " halt"