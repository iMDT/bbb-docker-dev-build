#!/bin/bash
DOCKER_USER=$1
DOCKER_PASS=$2
CIRCLE_BUILD_NUM=$3
IMAGE_NAME=bbb_`date '+%s'`
set -e
echo "Docker login"
docker login -u $DOCKER_USER -p $DOCKER_PASS
echo "Docker commit"
docker commit bbb_docker_build $IMAGE_NAME
echo "Docker tag"
docker tag $IMAGE_NAME imdt/bigbluebutton:3.0.x-develop
docker tag $IMAGE_NAME imdt/bigbluebutton:3.0.x-develop_build_$CIRCLE_BUILD_NUM
echo "Docker push"
docker push imdt/bigbluebutton:3.0.x-develop
docker push imdt/bigbluebutton:3.0.x-develop_build_$CIRCLE_BUILD_NUM
echo "Docker logout"
docker logout
