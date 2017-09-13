#!/usr/bin/bash

set -e
set -x
function modify-docker() {
	echo "------------------------------------------------------------"
	echo "modify docker service file ..."
	sudo mkdir -p /data/docker
cat <<EOF >/etc/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target firewalld.service
[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd --host=tcp://0.0.0.0:2375 -H unix:///var/run/docker.sock --selinux-enabled=false --graph=/data/docker
ExecReload=/bin/kill -s HUP $MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
[Install]
WantedBy=multi-user.target
EOF
	echo "start docker service ..."
	systemctl daemon-reload
	systemctl disable docker;systemctl enable docker
	systemctl restart docker
	iptables -P FORWARD ACCEPT
	echo "modify docker success"
	echo "------------------------------------------------------------"
}

function load_image() {
	echo "------------------------------------------------------------"
	echo "load image"
	cd /home/admin/k8s-auto-install/addons_images;
	for image in $(ls *.tar)
	do
		docker load -i $image
	done

	echo "load image success"
	echo "------------------------------------------------------------"
}

modify-docker
load_image