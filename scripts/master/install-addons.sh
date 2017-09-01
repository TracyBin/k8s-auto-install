#!/usr/bin/bash


set -e

INSTALL_ROOT=$(dirname "${BASH_SOURCE}")/../..
readonly MASTER_ROOT=$(dirname "${BASH_SOURCE}}")
source ${MASTER_ROOT}/environment.sh
KUBECTL="${CURRENT_HOME}/local/bin/kubectl"



function install-calico() {
	echo "------------------------------------------------------------"
	echo "install calico"
	
	ETCD_KEY=`cat /etc/etcd/ssl/etcd-key.pem | base64 | tr -d '\n'`
	ETCD_CERT=`cat /etc/etcd/ssl/etcd.pem | base64 | tr -d '\n'`
	ETCD_CA=`cat /etc/kubernetes/ssl/ca.pem | base64 | tr -d '\n'`
	
	sed -e "s|\$ETCD_ENDPOINTS|${ETCD_ENDPOINTS}|g" -e "s/\\\$ETCD_KEY_BASE64/${ETCD_KEY}/g" -e "s/\\\$ETCD_CERT_BASE64/${ETCD_CERT}/g" -e "s/\\\$ETCD_CA_BASE64/${ETCD_CA}/g"  "${INSTALL_ROOT}/calico/calico.yaml.sed" > ${INSTALL_ROOT}/calico/calico.yaml
	
	CALICO=`eval "${KUBECTL} get pods -n kube-system |grep calico | cat"`
	if [ ! "${CALICO}" ]; then
		${KUBECTL} create -f ${INSTALL_ROOT}/calico/rbac.yaml
		${KUBECTL} create -f ${INSTALL_ROOT}/calico/calico.yaml
		echo "calico is successfully deployed."
	else
		echo "calico is already deployed. Skipping."
	fi
	echo "------------------------------------------------------------"
}

function install-dns() {
	echo "------------------------------------------------------------"
	echo "install dns"
	DNS=`eval "${KUBECTL} get pods -n kube-system |grep dns | cat"`
	if [ ! "${DNS}" ]; then
		${KUBECTL} create -f ${INSTALL_ROOT}/kubedns/kubedns-cm.yaml
		${KUBECTL} create -f ${INSTALL_ROOT}/kubedns/kubedns-sa.yaml
		${KUBECTL} create -f ${INSTALL_ROOT}/kubedns/kubedns-controller.yaml
		${KUBECTL} create -f ${INSTALL_ROOT}/kubedns/kubedns-svc.yaml
		echo "dns is successfully deployed."
	else
		echo "dns is already deployed. Skipping."
	fi
	echo "------------------------------------------------------------"
}


function install-dashboard() {
	echo "------------------------------------------------------------"
	echo "install dashboard"
	DASHBOARD=`eval "${KUBECTL} get pods -n kube-system |grep dashboard | cat"`
	if [ ! "${DASHBOARD}" ]; then
		${KUBECTL} create -f ${INSTALL_ROOT}/dashboard/dashboard-rbac.yaml
		${KUBECTL} create -f ${INSTALL_ROOT}/dashboard/dashboard-controller.yaml
		${KUBECTL} create -f ${INSTALL_ROOT}/dashboard/dashboard-service.yaml
		echo "dashboard is successfully deployed."
	else
		echo "dashboard is already deployed. Skipping."
	fi
	echo "------------------------------------------------------------"
}
function install-heapster() {
	echo "------------------------------------------------------------"
	echo "install heapster"
	HEAPSTER=`eval "${KUBECTL} get pods -n kube-system |grep heapster | cat"`
	if [ ! "${HEAPSTER}" ]; then
		${KUBECTL} create -f ${INSTALL_ROOT}/heapster/heapster-rbac.yaml
		${KUBECTL} create -f ${INSTALL_ROOT}/heapster/influxdb.yaml
		${KUBECTL} create -f ${INSTALL_ROOT}/heapster/heapster.yaml
		echo "heapster is successfully deployed."
	else
		echo "heapster is already deployed. Skipping."
	fi
	echo "------------------------------------------------------------"
}

install-calico
install-dns
install-dashboard
install-heapster








