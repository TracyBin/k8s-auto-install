#!/bin/bash

set -e
INSTALL_ROOT=$(dirname "${BASH_SOURCE}")/../..
readonly MASTER_ROOT=$(dirname "${BASH_SOURCE}")
USER_HOME=${CURRENT_HOME}

SSH_OPTS="-oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=ERROR -C"

function usage() {
	echo "requires some arguments"
	echo "Usage: "
    echo "   install-master.sh  --master1 master1-ip --master2 master2-ip --master3 master1-ip --hostname current-host-name --ip current-host-ip --user user"
}

function load_image() {
	for image in $(ls ${INSTALL_ROOT}/addons_images/*.tar)
	do
		docker load -i $image
	done
}

function install-pre() {
	echo "------------------------------------------------------------"
	echo "install pre"
	# 验证参数是否完整
	if [ "${MASTER_1}" == "" ] || [ "${MASTER_2}" == "" ] || [ "${MASTER_3}" == "" ] || [ "${ETCD_NAME}" == "" ] || [ "${MASTER_ADDRESS}" == "" ] || [ "${CURRENT_USER}" == "" ]; then
		usage
		exit 1
	fi
	echo "disable firewalld NetworkManager"
	setenforce 0;
	iptables -P FORWARD ACCEPT;
	systemctl disable firewalld;systemctl disable NetworkManager;
	systemctl stop NetworkManager;systemctl stop firewalld;
	
	# 拷贝可执行文件到${CURRENT_HOME}/local/bin
	mkdir -p ${MASTER_ROOT}/certs/;
	chmod +x ${CURRENT_HOME}/local/bin/*
	sed -e "s/\\\$MASTER_1/${MASTER_1}/g" -e "s/\\\$MASTER_2/${MASTER_2}/g" -e "s/\\\$MASTER_3/${MASTER_3}/g" -e "s|\$CURRENT_HOME|${CURRENT_HOME}|g" "${MASTER_ROOT}/environment.sh.sed" > ${MASTER_ROOT}/environment.sh
	cp ${MASTER_ROOT}/environment.sh ${MASTER_ROOT}/certs/;
	source ${MASTER_ROOT}/environment.sh
	load_image
	echo "install pre success"
	echo "------------------------------------------------------------"
}

function make-cert() {
	echo "------------------------------------------------------------"
	echo "begin generate all the certs"
	cd ${MASTER_ROOT}/certs/;
	if [ -e "ca.pem" ]; then
		echo `pwd`
		echo "ca cert file exist,copy it"
	else
		echo "ca and etcd cert not exist,generate"
		rm -rf *.pem *.json
		# 生成CA配置文件
cat <<EOF > ca-config.json
{
	"signing": {
		"default": {
		"expiry": "87600h"
	},
	"profiles": {
		"kubernetes": {
			"usages": [
				"signing",
				"key encipherment",
				"server auth",
				"client auth"
			],
		"expiry": "87600h"
		}
	}
	}
}
EOF

echo "generate ca-csr"
# 生成CA签名请求
cat <<EOF >ca-csr.json
{
	"CN": "kubernetes",
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
cfssl gencert -initca ca-csr.json | cfssljson -bare ca


cat <<EOF  > etcd-csr.json
{
	"CN": "etcd",
	"hosts": [
		"127.0.0.1",
		"${MASTER_1}",
		"${MASTER_2}",
		"${MASTER_3}"
	],
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
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes etcd-csr.json | cfssljson -bare etcd

	echo "证书已生成到certs目录，请拷贝certs目录到所有的安装服务器...."
	echo "正在拷贝，请按照提示输入master服务器密码....."
	provision-master 
	echo "拷贝完成，暂停120秒，其他master服务同步执行此脚本...."
	sleep 30
fi



mkdir -p /etc/kubernetes/ssl /etc/etcd/ssl
chmod 755 ca* etcd*.pem
cp ca* /etc/kubernetes/ssl
cp etcd*.pem /etc/etcd/ssl;


echo "generate kubernetes certs"
# 创建 kubernetes 证书
cat <<EOF > kubernetes-csr.json 
{
	"CN": "kubernetes",
	"hosts": [
		"127.0.0.1",
		"${MASTER_ADDRESS}",
		"${CLUSTER_KUBERNETES_SVC_IP}",
		"kubernetes",
		"kubernetes.default",
		"kubernetes.default.svc",
		"kubernetes.default.svc.cluster",
		"kubernetes.default.svc.cluster.local"
	],
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

cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem -ca-key=/etc/kubernetes/ssl/ca-key.pem -config=/etc/kubernetes/ssl/ca-config.json -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes;
mkdir -p /etc/kubernetes/ssl/;
mv kubernetes*.pem /etc/kubernetes/ssl/;
rm -f kubernetes.csr kubernetes-csr.json

echo "generate token"
cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

mv token.csv /etc/kubernetes/

# 回到${MASTER_ROOT}目录下
cd ../;
echo "end generate certs,current directory:" + `pwd`
echo "generate all the certs success"
echo "---------------------------------------------" 
}

# 安装Etcd
function install-etcd {
	echo "---------------------------------------------" 
	echo "Begin to install etcd"
	# 解压etcd可执行文件包
	# cd ../../;tar xvf etcd-v3.2.5-linux-amd64.tar;
	# cp etcd-v3.2.5-linux-amd64/etcd* ${CURRENT_HOME}/local/bin;

	## Create etcd.conf, etcd.service, and start etcd service.
	etcd_data_dir=/var/lib/etcd
	mkdir -p ${etcd_data_dir} /etc/etcd
	
	ETCD_INITIAL_CLUSTER=${ETCD_NODES}
	
cat <<EOF > /etc/systemd/system/etcd.service 
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=http://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
EnvironmentFile=-/etc/etcd/etcd.conf
ExecStart=${CURRENT_HOME}/local/bin/etcd \
  --name=${ETCD_NAME} \
  --cert-file=/etc/etcd/ssl/etcd.pem \
  --key-file=/etc/etcd/ssl/etcd-key.pem \
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \
  --trusted-ca-file=/etc/kubernetes/ssl/ca.pem \
  --peer-trusted-ca-file=/etc/kubernetes/ssl/ca.pem \
  --initial-advertise-peer-urls=https://${MASTER_ADDRESS}:2380 \
  --listen-peer-urls=https://${MASTER_ADDRESS}:2380 \
  --listen-client-urls=https://${MASTER_ADDRESS}:2379,http://127.0.0.1:2379 \
  --advertise-client-urls=https://${MASTER_ADDRESS}:2379 \
  --initial-cluster-token=etcd-cluster-0 \
  --initial-cluster=${ETCD_INITIAL_CLUSTER} \
  --initial-cluster-state=new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

	echo "start etcd service..."
	systemctl daemon-reload
	systemctl disable etcd;systemctl enable etcd
	systemctl restart etcd
	echo "install etcd success"
	echo "---------------------------------------------" 
}


#配置kubectl命令行工具
function kubectl-util() {
	echo "------------------------------------------------------------"
	echo "config kubectl"
	KUBE_APISERVER="https://${MASTER_ADDRESS}:6443"
cat > admin-csr.json <<EOF
{
	"CN": "admin",
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
			"O": "system:masters",
			"OU": "System"
		}
	]
}
EOF
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem -ca-key=/etc/kubernetes/ssl/ca-key.pem -profile=kubernetes admin-csr.json | cfssljson -bare admin;
mv admin*.pem /etc/kubernetes/ssl/;
rm admin.csr admin-csr.json

kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/ssl/ca.pem --embed-certs=true --server=${KUBE_APISERVER};
kubectl config set-credentials admin --client-certificate=/etc/kubernetes/ssl/admin.pem --embed-certs=true --client-key=/etc/kubernetes/ssl/admin-key.pem;
kubectl config set-context kubernetes --cluster=kubernetes --user=admin;
kubectl config use-context kubernetes
cp /root/.kube/config ${MASTER_ROOT}/certs/;chmod 755 ${MASTER_ROOT}/certs/config
echo "config kubectl success"
echo "------------------------------------------------------------"
}


# 安装kube-apiserver
function install-apiserver() {
	echo "------------------------------------------------------------"
	echo "Begin to install kube-apiserver"

	SERVICE_CLUSTER_IP_RANGE="10.254.0.0/16"
	ADMISSION_CONTROL="NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota"

	echo "begin generate apiserver config"
cat > /etc/systemd/system/kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=http://github.com/GoogleCloudPlatform/kubernetes
After=network.target
[Service]
ExecStart=${CURRENT_HOME}/local/bin/kube-apiserver \\
--admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
--advertise-address=${MASTER_ADDRESS} \\
--bind-address=${MASTER_ADDRESS} \\
--insecure-bind-address=${MASTER_ADDRESS} \\
--authorization-mode=RBAC \\
--runtime-config=rbac.authorization.k8s.io/v1alpha1 \\
--kubelet-https=true \\
--experimental-bootstrap-token-auth \\
--token-auth-file=/etc/kubernetes/token.csv \\
--service-cluster-ip-range=${SERVICE_CIDR} \\
--service-node-port-range=${NODE_PORT_RANGE} \\
--tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \\
--tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \\
--client-ca-file=/etc/kubernetes/ssl/ca.pem \\
--service-account-key-file=/etc/kubernetes/ssl/ca-key.pem \\
--etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
--etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \\
--etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \\
--etcd-servers=${ETCD_ENDPOINTS} \\
--enable-swagger-ui=true \\
--allow-privileged=true \\
--apiserver-count=3 \\
--audit-log-maxage=30 \\
--audit-log-maxbackup=3 \\
--audit-log-maxsize=100 \\
--audit-log-path=/var/lib/audit.log \\
--event-ttl=1h \\
--v=4
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

	echo "start apiserver service..."
	systemctl daemon-reload
	systemctl disable kube-apiserver;systemctl enable kube-apiserver
	systemctl restart kube-apiserver
	echo "install kube-apiserver success"
	echo "------------------------------------------------------------"
}


function install-controller() {
	echo "------------------------------------------------------------"
	echo "Begin to install kube-controller-manager"
	
	echo "begin generate controller config"
cat > /etc/systemd/system/kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=http://github.com/GoogleCloudPlatform/kubernetes
[Service]
ExecStart=${CURRENT_HOME}/local/bin/kube-controller-manager \\
--address=127.0.0.1 \\
--master=http://${MASTER_ADDRESS}:8080 \\
--service-cluster-ip-range=${SERVICE_CIDR} \\
--cluster-name=kubernetes \\
--cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \\
--cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \\
--service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem \\
--root-ca-file=/etc/kubernetes/ssl/ca.pem \\
--leader-elect=true \\
--v=4
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
	
	echo "start controller service..."
	systemctl daemon-reload
	systemctl disable kube-controller-manager;systemctl enable kube-controller-manager
	systemctl restart kube-controller-manager
	echo "install kube-controller-manager success"
	echo "------------------------------------------------------------"
}



function install-scheduler() {
	echo "------------------------------------------------------------"
	echo "Begin to install kube-scheduler"
	###
	echo "begin generate scheduler config"
cat > /etc/systemd/system/kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=http://github.com/GoogleCloudPlatform/kubernetes
[Service]
ExecStart=${CURRENT_HOME}/local/bin/kube-scheduler \\
--address=127.0.0.1 \\
--master=http://${MASTER_ADDRESS}:8080 \\
--leader-elect=true \\
--v=4
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

	echo "start scheduler service..."
	systemctl daemon-reload
	systemctl disable kube-scheduler;systemctl enable kube-scheduler
	systemctl restart kube-scheduler
	echo "install kube-scheduler success"
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

function provision-master() {
	local MASTERS=(${MASTER_2} ${MASTER_3})
	echo `pwd`
	for master in ${MASTERS[@]}
	do
		kube-scp "${master}" "*" "${CURRENT_HOME}/k8s-auto-install/scripts/master/certs/"
	done
}

function sync-master() {
	local MASTERS=(${MASTER_2} ${MASTER_3})
	echo `pwd`
	for master in ${MASTERS[@]}
	do
		kube-ssh "${master}" "sudo bash ${CURRENT_HOME}/k8s-auto-install/scripts/master/install-master.sh --master1 ${MASTER_1} --master2 ${MASTER_2} --master3 ${MASTER_3} --hostname ${ETCD_NAME} --ip ${MASTER_ADDRESS} >>${CURRENT_HOME}/install.log $"
	done
}


# Run command over ssh
function kube-ssh() {
  local host="$1"
  shift
  ssh ${SSH_OPTS} -t "${host}" "$@" >/dev/null 2>&1
}

# 分发安装文件到所有的master机器
# Copy file recursively over ssh
function kube-scp() {
  local host="$1"
  local src=($2)
  local dst="$3"
  scp -r ${SSH_OPTS} ${src[*]} "${CURRENT_USER}@${host}:${dst}"
}




ARGS=`getopt -o a:b:c:d:e:f: --long master1:,master2:,master3:,hostname:,ip:,user: -n 'etcd.sh' -- "$@"`
if [ $? != 0 ]; then
	echo "Terminating...."
	exit 1
fi

#将规范化后的命令行参数分配至位置参数（$1,$2,...)
eval set -- "${ARGS}"

while true
do  
    case $1 in  
        -a|--master1)  
            export MASTER_1=$2;
	    shift 2
	    ;;  
		-b|--master2)  
			export MASTER_2=$2;
			shift 2
			;;  
		-c|--master3)  
			export MASTER_3=$2;
			shift 2
			;;
		-d|--hostname)
			export ETCD_NAME=$2;
			hostnamectl set-hostname --static ${ETCD_NAME}
			shift 2
			;;
		-e|--ip)
			export MASTER_ADDRESS=$2;
			shift 2
			;;
		-f|--user)
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
			echo "   install-master.sh  --master1 master1-ip --master2 master1-ip --master3 master1-ip --hostname current-host-name --ip current-host-ip --user user"
			exit 1
			;;
    esac
done
modify-docker
install-pre
make-cert
echo "Install etcd apiserver controller-manage schedule in ${ETCD_NAME}, IP:${MASTER_ADDRESS},USER:${CURRENT_USER}"
echo "etcd cluster:${ETCD_NODES}"
install-etcd
kubectl-util
install-apiserver
install-controller
install-scheduler


