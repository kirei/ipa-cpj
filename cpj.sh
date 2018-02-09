#!/bin/bash
#
# Container PKI Janitor
#
# Copyright (c) 2017, Kirei AB
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


HOST_CERTDIR=/etc/pki/cpj
DOCKER_DESTDIR=/etc/pki
DOCKER_CONTAINER_DIR=/var/lib/docker/containers
HOSTNAME=`hostname`

function request_cert() {
  local container_dockerid=$1
  local container_fqdn=$2
  local container_ipaddress=$3

  ipa host-add ${container_fqdn} --ip-address=${container_ipaddress} --no-reverse --desc "Container at $HOSTNAME"
  ipa host-add-managedby ${container_fqdn} --hosts=$HOSTNAME

  ipa-getcert request \
    -I ${container_dockerid} \
    -C "$0 install ${container_dockerid}" \
    -k ${HOST_CERTDIR}/${container_dockerid}.key \
    -f ${HOST_CERTDIR}/${container_dockerid}.crt \
    -N CN=${container_fqdn} \
    -D ${container_fqdn} \
    -K HOST/${container_fqdn}
}

function revoke_cert() {
  local container_dockerid=$1
  local container_fqdn=$2

  ipa-getcert stop-tracking -i ${container_dockerid}

  rm ${HOST_CERTDIR}/${container_dockerid}.crt
  rm ${HOST_CERTDIR}/${container_dockerid}.key

  if [ -n "${container_fqdn}" ]; then
    ipa host-del ${container_fqdn}
  fi
}

function install_cert() {
  local container_dockerid=$1

  if [ -f ${HOST_CERTDIR}/${container_dockerid}.crt -a -f ${HOST_CERTDIR}/${container_dockerid}.key ]; then
    docker exec ${container_dockerid} mkdir ${DOCKER_DESTDIR}
    docker cp ${HOST_CERTDIR}/${container_dockerid}.crt ${container_dockerid}:${DOCKER_DESTDIR}/host.crt && \
    docker cp ${HOST_CERTDIR}/${container_dockerid}.key ${container_dockerid}:${DOCKER_DESTDIR}/host.key && \
    touch ${HOST_CERTDIR}/${container_dockerid}.installed
  fi
}

function process_new_containers() {
  for container_dockerid in `docker ps --format '{{.ID}}'`; do
    local container_ipaddress=`docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $container_dockerid`
    local container_hostname=`docker inspect --format='{{.Config.Hostname}}' $container_dockerid`
    local container_domainname=`docker inspect --format='{{.Config.Domainname}}' $container_dockerid`
    if [ -z "${container_domainname}" ]; then
      container_domainname=`hostname --domain`
    fi
    local container_fqdn="${container_hostname}.${container_domainname}"

    echo "Processing certs for docker_id $container_dockerid ($container_ipaddress, ${container_fqdn})"

    if [ ! -f ${HOST_CERTDIR}/${container_dockerid}.crt ]; then
      request_cert $container_dockerid ${container_fqdn} ${container_ipaddress}
    else
      if [ ! -f ${HOST_CERTDIR}/${container_dockerid}.installed ]; then
        install_cert ${container_dockerid}
      fi
    fi
  done
}

function process_removed_containers() {
  for container_certfile in `ls -1 ${HOST_CERTDIR}/*.crt`; do
    container_dockerid=`basename ${container_certfile} .crt`
    docker ps -a --format '{{.ID}}' | grep -q $container_dockerid
    if [ $? -ne 0 ]; then
      # container is no more, revoke certificate
      container_fqdn=`openssl x509 -subject -noout -in ${HOST_CERTDIR}/${container_dockerid}.crt | sed 's/.* CN = //'`
      revoke_cert $container_dockerid $container_fqdn
    fi
  done
}

case $1 in
  scan)
    test -d $HOST_CERTDIR || mkdir -p $HOST_CERTDIR
    kinit -k -t /etc/krb5.keytab
    process_new_containers
    process_removed_containers
    ;;
  install)
    install_cert $2
    ;;
  *)
    echo "Invalid mode of operation, usage: $0 [scan|install]"
    exit 1
esac
