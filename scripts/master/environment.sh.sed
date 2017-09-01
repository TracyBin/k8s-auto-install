#!/usr/bin/bash

# TLS Bootstrapping 使用的 Token，可以使用命令 head -c 16 /dev/urandom | od -An -t x | tr -d ' ' 生成
BOOTSTRAP_TOKEN="7007baae247a3bcd73f9cb9ea24f618c"

export PATH=$CURRENT_HOME/local/bin:$PATH

# 最好使用 主机未用的网段 来定义服务网段和 Pod 网段

# 服务网段 (Service CIDR），部署前路由不可达，部署后集群内使用IP:Port可达
SERVICE_CIDR="10.254.0.0/16"

# POD 网段 (Cluster CIDR），部署前路由不可达，**部署后**路由可达(flanneld保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
export NODE_PORT_RANGE="30000-32767"

# etcd 集群服务地址列表
export ETCD_ENDPOINTS="https://$MASTER_1:2379,https://$MASTER_2:2379,https://$MASTER_3:2379"

export NODE_IPS="$MASTER_1 $MASTER_2 $MASTER_3"

# etcd 集群间通信的IP和端口
export ETCD_NODES=master-1=https://$MASTER_1:2380,master-2=https://$MASTER_2:2380,master-3=https://$MASTER_3:2380

# kubernetes 服务 IP (一般是 SERVICE_CIDR 中第一个IP)
export CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
export CLUSTER_DNS_DOMAIN="cluster.local."

export CURRENT_HOME=$CURRENT_HOME
