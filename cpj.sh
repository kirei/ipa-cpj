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
DOCKER_SUBDOMAIN=containers.
HOSTNAME=`hostname`

function add_principal() {
  local container_fqdn=$1

  ipa host-add ${container_fqdn} --force --desc "Container at $HOSTNAME"
  ipa host-add-managedby ${container_fqdn} --hosts=$HOSTNAME
}

function request_cert() {
  local container_fqdn=$1
  local container_dockerid=$2

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

  rm ${HOST_CERTDIR}/${container_dockerid}.*

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
    local container_hostname=`docker inspect --format='{{.Config.Hostname}}' $container_dockerid`
    local container_domainname=`docker inspect --format='{{.Config.Domainname}}' $container_dockerid`
    if [ -z "${container_domainname}" ]; then
      container_domainname=${DOCKER_SUBDOMAIN}`hostname --domain`
    fi
    local container_fqdn="${container_hostname}.${container_domainname}"

    if [ ! -f ${HOST_CERTDIR}/${container_dockerid}.principal ]; then
      echo "Adding principal for docker_id $container_dockerid (${container_fqdn})"
      add_principal $container_fqdn
      touch ${HOST_CERTDIR}/${container_dockerid}.principal
    fi
  done

  for container_dockerid in `docker ps --format '{{.ID}}'`; do
    local container_hostname=`docker inspect --format='{{.Config.Hostname}}' $container_dockerid`
    local container_domainname=`docker inspect --format='{{.Config.Domainname}}' $container_dockerid`
    if [ -z "${container_domainname}" ]; then
      container_domainname=${DOCKER_SUBDOMAIN}`hostname --domain`
    fi
    local container_fqdn="${container_hostname}.${container_domainname}"

    if [ ! -f ${HOST_CERTDIR}/${container_dockerid}.crt -a -f ${HOST_CERTDIR}/${container_dockerid}.principal ]; then
      echo "Requesting cert for docker_id $container_dockerid (${container_fqdn})"
      request_cert $container_fqdn $container_dockerid 
    fi
  done
}

function install_pending_certs() {
  for container_dockerid in `docker ps --format '{{.ID}}'`; do
    if [ -f ${HOST_CERTDIR}/${container_dockerid}.crt -a ! -f ${HOST_CERTDIR}/${container_dockerid}.installed ]; then
      echo "Installing cert for docker_id $container_dockerid"
      install_cert $container_dockerid
    fi
  done
}

function resubmit_certs() {
  for container_keyfile in `ls -1 ${HOST_CERTDIR}/*.key`; do
    container_dockerid=`basename ${container_keyfile} .key`
    if [ ! -f ${HOST_CERTDIR}/${container_dockerid}.crt -a -f ${HOST_CERTDIR}/${container_dockerid}.principal ]; then
      # initial cert request failed, resubmit
      ipa-getcert resubmit -i $container_dockerid
    fi
  done
}

function process_removed_containers() {
  for container_certfile in `ls -1 ${HOST_CERTDIR}/*.crt`; do
    container_dockerid=`basename ${container_certfile} .crt`
    docker ps -a --format '{{.ID}}' | grep -q $container_dockerid
    if [ $? -ne 0 ]; then
      # container is no more, revoke certificate
      container_fqdn=`openssl x509 -subject -noout -in ${HOST_CERTDIR}/${container_dockerid}.crt | sed 's,.*/CN=,,'`
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
    sleep 10
    resubmit_certs
    sleep 10
    install_pending_certs
    ;;
  install)
    install_cert $2
    ;;
  resubmit)
    resubmit_certs
    ;;
  *)
    echo "Invalid mode of operation, usage: $0 [scan|install]"
    exit 1
esac
