#!/bin/bash


set -e
INSTALL_ROOT=$(dirname "${BASH_SOURCE}")/../..
readonly CURRENT_DIR=$(cd `dirname $0`; pwd)
SSH_OPTS="-oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=ERROR -C"


function usage() {
	echo "requires some arguments"
	echo "Usage: "
    echo "   install-node.sh  --master master-ip --hostname current-host-name --nodeip current-host-ip --user user "
}

function load_image() {
	echo "------------------------------------------------------------"
	echo "load image"

	for image in $(ls ${INSTALL_ROOT}/addons_images/*.tar)
	do
		docker load -i $image
	done

	echo "load image success"
	echo "------------------------------------------------------------"
}


# Copy file from the remote to local
function kube-scp() {
  local remote="$1"
  local local="$2"
  echo ${remote}
  echo ${local}
  scp -r ${SSH_OPTS} ${remote} "${local}"
}

function copy-certs() {
	local SRC_DIR=${CURRENT_HOME}/k8s-auto-install/scripts;
	mkdir -p ${SRC_DIR}/node/certs
	kube-scp "${CURRENT_USER}@${MASTER_ADDRESS}:${SRC_DIR}/master/certs/*" "${SRC_DIR}/node/certs"
	# 环境变量和kubeconfig文件一并从master拷贝到node节点
	mv ${SRC_DIR}/node/certs/environment.sh ${CURRENT_DIR}/
	mkdir -p /root/.kube
	mv ${SRC_DIR}/node/certs/config /root/.kube/
}

function install-pre() {
	echo "------------------------------------------------------------"
	echo "ready the precondition"
	# 验证参数是否完整
	if [ "${MASTER_ADDRESS}" == "" ] || [ "${NODE_ADDRESS}" == "" ] || [ "${NODE_NAME}" == "" ] || [ "${CURRENT_USER}" == "" ]; then
		usage
		exit 1
	fi
	
	# 拷贝master节点环境变量
	copy-certs
	# 执行环境变量
	chmod +x ${CURRENT_DIR}/environment.sh
	source ${CURRENT_DIR}/environment.sh
	
	chmod +x ${CURRENT_HOME}/local/bin/* 
	
	setenforce 0;
	iptables -P FORWARD ACCEPT;
	systemctl disable firewalld;systemctl disable NetworkManager;
	systemctl stop NetworkManager;systemctl stop firewalld;
	
	# 开启ipv4转发
	if [ -z "`grep "net.ipv4.ip_forward"  /etc/sysctl.conf`" ]; then
cat <<EOF  >> /etc/sysctl.conf
net.ipv4.ip_forward = 1
EOF
    fi
	
	# centos7内核转发需要额外的设置
	if [ -z "`grep "net.ipv4.ip_forward" /usr/lib/sysctl.d/50-default.conf`" ]; then
cat <<EOF >> /usr/lib/sysctl.d/50-default.conf
net.ipv4.ip_forward = 1
EOF
	fi
	sysctl -p
	load_image
	
	#拷贝证书
	mkdir -p /etc/kubernetes/ssl
	cp ${CURRENT_DIR}/../node/certs/ca* /etc/kubernetes/ssl
	
	echo "the precondition success"
	echo "------------------------------------------------------------"
}


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


function install-kubelet() {
	echo "------------------------------------------------------------"
	echo "install kubelet..."
	DNS_SERVER_IP=${CLUSTER_DNS_SVC_IP}
	DNS_DOMAIN=${CLUSTER_DNS_DOMAIN}
	
	CLUSTER_ROLE_BIND=`eval kubectl get clusterrolebinding/kubelet-bootstrap | cat`
	if [ ! "${CLUSTER_ROLE_BIND}" ]; then
		kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
	fi
	kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/ssl/ca.pem --embed-certs=true --server=${KUBE_APISERVER} --kubeconfig=bootstrap.kubeconfig;
	kubectl config set-credentials kubelet-bootstrap --token=${BOOTSTRAP_TOKEN} --kubeconfig=bootstrap.kubeconfig;
	kubectl config set-context default --cluster=kubernetes  --user=kubelet-bootstrap --kubeconfig=bootstrap.kubeconfig;
	kubectl config use-context default --kubeconfig=bootstrap.kubeconfig;
	mv bootstrap.kubeconfig /etc/kubernetes/

	mkdir -p /var/lib/kubelet;
cat <<EOF > /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=http://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=${CURRENT_HOME}/local/bin/kubelet \
  --address=${NODE_ADDRESS} \
  --hostname-override=${NODE_NAME} \
  --pod-infra-container-image=registry.access.redhat.com/rhel7/pod-infrastructure:latest \
  --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
  --kubeconfig=/etc/kubernetes/kubelet-kubeconfig \
  --require-kubeconfig \
  --cert-dir=/etc/kubernetes/ssl \
  --container-runtime=docker \
  --cluster-dns=${CLUSTER_DNS_SVC_IP} \
  --cluster-domain=${CLUSTER_DNS_DOMAIN} \
  --hairpin-mode promiscuous-bridge \
  --allow-privileged=true \
  --serialize-image-pulls=false \
  --register-node=true \
  --logtostderr=true \
  --network-plugin=cni \
  --v=2
ExecStopPost=/sbin/iptables -A INPUT -s 10.0.0.0/8 -p tcp --dport 4194 -j ACCEPT
ExecStopPost=/sbin/iptables -A INPUT -s 172.16.0.0/12 -p tcp --dport 4194 -j ACCEPT
ExecStopPost=/sbin/iptables -A INPUT -s 192.168.0.0/16 -p tcp --dport 4194 -j ACCEPT
ExecStopPost=/sbin/iptables -A INPUT -p tcp --dport 4194 -j DROP
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

	echo "start kubelet..."
	systemctl daemon-reload
	systemctl disable kubelet;systemctl enable kubelet
	systemctl restart kubelet
	echo "install kubelet success"
	echo "------------------------------------------------------------"
}





function install-proxy() {
	echo "------------------------------------------------------------"
	echo "install kube-proxy..."
cat <<EOF > kube-proxy-csr.json 
{
	"CN": "system:kube-proxy",
	"hosts": [],
	"key": {
	"algo": "rsa",
	"size": 2048
	},
	"names": [
		{
			"C": "CN",
			"ST": "BeiJing",
			"L": "BeiJing",
			"O": "k8s",
			"OU": "System"
		}
	]
}
EOF

cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem -ca-key=/etc/kubernetes/ssl/ca-key.pem  -config=/etc/kubernetes/ssl/ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy;
mv kube-proxy*.pem /etc/kubernetes/ssl/;
rm -f  kube-proxy.csr kube-proxy-csr.json
	
kubectl config set-cluster kubernetes  --certificate-authority=/etc/kubernetes/ssl/ca.pem --embed-certs=true --server=${KUBE_APISERVER} --kubeconfig=kube-proxy.kubeconfig;
kubectl config set-credentials kube-proxy --client-certificate=/etc/kubernetes/ssl/kube-proxy.pem  --client-key=/etc/kubernetes/ssl/kube-proxy-key.pem --embed-certs=true --kubeconfig=kube-proxy.kubeconfig;
kubectl config set-context default --cluster=kubernetes --user=kube-proxy --kubeconfig=kube-proxy.kubeconfig;kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig;
mv kube-proxy.kubeconfig /etc/kubernetes/
	
mkdir -p /var/lib/kube-proxy;
cat <<EOF > /etc/systemd/system/kube-proxy.service 
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=http://github.com/GoogleCloudPlatform/kubernetes
After=network.target
[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=${CURRENT_HOME}/local/bin/kube-proxy \\
--bind-address=${NODE_ADDRESS} \\
--hostname-override=${NODE_NAME} \\
--cluster-cidr=${SERVICE_CIDR} \\
--kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
--logtostderr=true \\
--v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
	echo "start kube-proxy..."
	systemctl daemon-reload
	systemctl disable kube-proxy;systemctl enable kube-proxy
	systemctl restart kube-proxy
	echo "install kube-proxy success"
	echo "------------------------------------------------------------"
}



ARGS=`getopt -o a:b:c:d: --long master:,hostname:,nodeip:,user: -n 'install-node.sh' -- "$@"`
if [ $? != 0 ]; then
	echo "Terminating...."
	exit 1
fi

#将规范化后的命令行参数分配至位置参数（$1,$2,...)
eval set -- "${ARGS}"

while true
do  
    case $1 in  
        -a|--master)  
            export MASTER_ADDRESS=$2;
			export KUBE_APISERVER="https://${MASTER_ADDRESS}:6443"
	    shift 2
	    ;;
		-b|--hostname)
			export NODE_NAME=$2;
			hostnamectl set-hostname --static ${NODE_NAME}
			shift 2
			;;
		-c|--nodeip)  
			export NODE_ADDRESS=$2;
			shift 2
			;;
		-d|--user)
			export CURRENT_USER=$2;
			export CURRENT_HOME="/home/${CURRENT_USER}"
			shift 2
			;;
		--)  
			shift
			break
			;;
		*)
			echo "Usage: "
			echo "   install-node.sh  --master master-ip --hostname current-host-name --nodeip current-host-ip --user user"
			exit 1
			;;
    esac
done
echo "------------------------------------------------------------"
echo "Install kubelet,kube-proxy in Node:${NODE_ADDRESS},${NODE_NAME};MASTER_ADDRESS:${MASTER_ADDRESS}"
echo "------------------------------------------------------------"
modify-docker
install-pre
install-kubelet
install-proxy




