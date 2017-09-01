#!/usr/bin/bash
set -x
INSTALL_ROOT=$(dirname "${BASH_SOURCE}")/../..
readonly MASTER_ROOT=$(dirname "${BASH_SOURCE}}")

KUBECTL="${CURRENT_HOME}/local/bin/kubectl"

DNS=`eval "${KUBECTL} get pods -n kube-system |grep dns | cat"`
if [ "${DNS}" ]; then
	${KUBECTL} delete -f ${INSTALL_ROOT}/kubedns/kubedns-cm.yaml
	${KUBECTL} delete -f ${INSTALL_ROOT}/kubedns/kubedns-sa.yaml
	${KUBECTL} delete -f ${INSTALL_ROOT}/kubedns/kubedns-controller.yaml
	${KUBECTL} delete -f ${INSTALL_ROOT}/kubedns/kubedns-svc.yaml
	echo "dns is successfully uninstall."
else
	echo "dns is successfully uninstall.skipping"
fi

HEAPSTER=`eval "${KUBECTL} get pods -n kube-system |grep heapster | cat"`
if [ "${HEAPSTER}" ]; then
	${KUBECTL} delete -f ${INSTALL_ROOT}/heapster/heapster-rbac.yaml
	${KUBECTL} delete -f ${INSTALL_ROOT}/heapster/influxdb.yaml
	${KUBECTL} delete -f ${INSTALL_ROOT}/heapster/heapster.yaml
	echo "heapster is successfully uninstall."
else
	echo "heapster is successfully uninstall.skipping"
fi

DASHBOARD=`eval "${KUBECTL} get pods -n kube-system |grep dashboard | cat"`
if [ "${DASHBOARD}" ]; then
	${KUBECTL} delete -f ${INSTALL_ROOT}/dashboard/dashboard-rbac.yaml
	${KUBECTL} delete -f ${INSTALL_ROOT}/dashboard/dashboard-controller.yaml
	${KUBECTL} delete -f ${INSTALL_ROOT}/dashboard/dashboard-service.yaml
	echo "dashboard is successfully uninstall."
else
	echo "dashboard is successfully uninstall.skipping"
fi

CALICO=`eval "${KUBECTL} get pods -n kube-system |grep calico | cat"`
if [ "${CALICO}" ]; then
	${KUBECTL} delete -f ${INSTALL_ROOT}/calico/rbac.yaml
	${KUBECTL} delete -f ${INSTALL_ROOT}/calico/calico.yaml
	echo "calico is successfully uninstall."
else
	echo "calico is successfully uninstall.skipping"
fi

CLUSTER_ROLE_BIND=`eval kubectl get clusterrolebinding/kubelet-bootstrap | cat`
if [ "${CLUSTER_ROLE_BIND}" ]; then
	${KUBECTL} delete clusterrolebinding/kubelet-bootstrap
fi


systemctl stop kube-apiserver kube-controller-manager kube-scheduler etcd kubelet kube-proxy;
systemctl disable kube-apiserver kube-controller-manager kube-scheduler etcd kubelet kube-proxy;

rm -rf /etc/systemd/system/kube*.service /etc/systemd/system/etcd*.service
rm -rf /etc/kubernetes
rm -rf /etc/etcd /var/lib/etcd
rm -rf ${MASTER_ROOT}/certs/*



