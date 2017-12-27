# k8s-auto-install ----Asiainfo-CMC-JF
> 根据k8s官方社区的centos版本的安装脚本，根据自己的需求和安装场景进行了改编，使kubernetes高可用环境能半自动化部署

> 脚本安装完成后，所有的组件均使用TLS加密通信，部署架构为：三台master节点，N台node节点，master节点可与node节点合用

> **所有的安装均以admin用户为例，有sudo权限**
> 二进制文件百度网盘 https://pan.baidu.com/s/1i5MU721

### 安装前置条件
- centos7 
- docker 1.13.1,docker默认的存储位置在/data/docker,如需更改存储位置，需要修改 modify-docker函数中的docker启动参数--graph
- k8s 1.6.6版本各个组件的二进制安装包
`etcd  etcdctl kube-apiserver kube-controller-manager kube-scheduler kubectl kubelet kube-proxy`
- TLS加密工具
`cfssl cfssl-certinfo cfssljson`
- clone本项目到本地k8s-auto-install目录
- 组件镜像 calico dns dashboard heapster influxdb,列表如下
```
calico/node:v2.5.0
calico/kube-policy-controller:v0.7.0
calico/cni:v1.10.0
gcr.io/google_containers/pause-amd64:3.0
heapster-amd64:v1.3.0
registry.access.redhat.com/rhel7/pod-infrastructure:latest
k8s-dns-dnsmasq-nanny-amd64:v1.14.1
k8s-dns-kube-dns-amd64:v1.14.1
k8s-dns-sidecar-amd64:v1.14.1
kubernetes-dashboard-amd64:v1.6.0
heapster-influxdb-amd64:v1.1.1
```

三台master节点为  master-1(10.12.2.151)  master-2(10.12.2.152)  master-3(10.12.2.153)
节点hostname不需要单独设置，脚本会自动设置本地hostname.
node节点与master节点合用

### master和etcd集群安装步骤
#### 1、拷贝安装包
- 拷贝所有的二进制安装包到所有的节点/home/admin/local/bin目录下
- 拷贝k8s-auto-install目录到所有的节点/home/admin目录下
- 拷贝所有的组件镜像到所有的节点/home/admin/k8s-auto-install/addons_images目录下
> 拷贝完成后，所有节点均需存在如下安装包（镜像tar包名字可有不同，但docker images后的标签必须与上面提到的相同）
```
[admin@master-1 ~]$ pwd
/home/admin
[admin@master-1 ~]$ ll k8s-auto-install/
total 20
drwxrwxr-x. 2 admin admin  4096 Sep  1 10:00 addons_images
drwxrwxr-x. 2 admin admin    65 Aug 31 18:39 calico
drwxrwxr-x. 2 admin admin    96 Aug 31 16:48 dashboard
drwxrwxr-x. 2 admin admin    74 Aug 31 16:48 heapster
drwxrwxr-x. 2 admin admin   107 Aug 31 16:48 kubedns
-rw-rw-r--. 1 admin admin 11357 Sep  1 10:25 LICENSE
-rw-rw-r--. 1 admin admin    63 Sep  1 10:25 README.md
drwxrwxr-x. 4 admin admin    50 Aug 31 16:48 scripts
[admin@master-1 ~]$ ll k8s-auto-install/addons_images/
total 1890836
-rwxrwxr-x. 1 admin admin  70521856 Aug 30 16:36 calico-cni-1.10.0.tar
-rwxrwxr-x. 1 admin admin 282505728 Aug 30 16:37 calico-node-2.5.0.tar
-rwxrwxr-x. 1 admin admin  22447616 Aug 30 16:35 calico-policy-controller-0.7.0.tar
-rwxrwxr-x. 1 admin admin  11809280 Aug 30 18:23 heapster-influxdb-amd64-v1.1.1.tar
-rwxrwxr-x. 1 admin admin  68125184 Aug 30 16:34 heapster-v1.3.0.tar
-rwxrwxr-x. 1 admin admin  45130240 Aug 30 16:34 k8s-dns-dnsmasq-nanny-amd64-v1.14.1.tar
-rwxrwxr-x. 1 admin admin  52617728 Aug 30 16:33 k8s-dns-kube-dns-amd64-v1.14.1.tar
-rwxrwxr-x. 1 admin admin  44777984 Aug 30 16:33 k8s-dns-sidecar-amd64-v1.14.1.tar
-rwxrwxr-x. 1 admin admin 108823552 Aug 30 16:34 kubernetes-dashboard-amd64-v1.6.0.tar
-rwxrwxr-x. 1 admin admin    765440 Aug 30 16:30 pause-amd.tar
-rwxrwxr-x. 1 admin admin 215748096 Aug 30 16:36 pod-infrastructure.tar
[admin@master-1 ~]$ ll local/bin/
total 732192
-rwxrwxr-x. 1 admin admin  10376657 Aug 30 16:30 cfssl
-rwxrwxr-x. 1 admin admin   6595195 Aug 30 16:30 cfssl-certinfo
-rwxrwxr-x. 1 admin admin   2277873 Aug 30 16:29 cfssljson
-rwxrwxr-x. 1 admin admin  17139744 Aug 30 16:29 etcd
-rwxrwxr-x. 1 admin admin  14648320 Aug 30 16:29 etcdctl
-rwxrwxr-x. 1 admin admin 149544650 Aug 30 16:32 kube-apiserver
-rwxrwxr-x. 1 admin admin 131805645 Aug 30 16:32 kube-controller-manager
-rwxrwxr-x. 1 admin admin  70704763 Aug 30 16:28 kubectl
-rwxrwxr-x. 1 admin admin 138843648 Aug 30 16:30 kubelet
-rwxrwxr-x. 1 admin admin  64015718 Aug 30 16:28 kube-proxy
-rwxrwxr-x. 1 admin admin  75646283 Aug 30 16:28 kube-scheduler
```

#### 2、安装master和etcd集群
- 在master-1执行如下命令
```
cd /home/admin/k8s-auto-install/scripts/master;
./install-master.sh  --master1 10.12.2.151 --master2 10.12.2.152 --master3 10.12.2.153 --hostname master-1 --ip 10.12.2.151 --user admin
```
> 脚本执行过程中，会提示输入master-2和master-3节点admin用户的密码，输入密码后，会自动下发密钥和证书到master-2和master-3节点
- 证书自动下发完毕后，master-1脚本执行会暂停30秒，等待master-2和master-3执行脚本
> 这里中断30秒的目的是，需要所有master节点同时安装启动etcd服务，否则安装会中断
- 在master-2和master-3分别执行如下命令

```
cd /home/admin/k8s-auto-install/scripts/master;
sudo ./install-master.sh  --master1 10.12.2.151 --master2 10.12.2.152 --master3 10.12.2.153 --hostname master-2 --ip 10.12.2.152 --user admin
```

```
cd /home/admin/k8s-auto-install/scripts/master;
sudo ./install-master.sh  --master1 10.12.2.151 --master2 10.12.2.152 --master3 10.12.2.153 --hostname master-3 --ip 10.12.2.153 --user admin
```

- 等待master节点均安装完毕，验证各个组件是否正常工作：在master-1节点执行如下命令
```
sudo /home/admin/local/bin/kubectl get cs
```

#### 3、安装node节点
- 以在master-1上安装node节点为例，执行如下命令安装node节点
```
cd /home/admin/k8s-auto-install/scripts/node;
sudo ./install-node.sh  --master 10.12.2.151 --hostname master-1 --nodeip 10.12.2.151 --user admin
```
> 此脚本执行过程中会拉取master节点上的证书，需要输入--master节点的admin用户密码
> hostname为node节点本身的主机名  user为当前安装的linux用户
> 在其他node节点安装时，只需修改--hostname和--nodeip参数即可
- node节点安装完毕后，需要在master节点手动执行如下命令，允许node节点加入(这部分无法做到自动化，官方文档有说明)
```
[admin@master-1 ~]$ sudo ./local/bin/kubectl get csr
NAME        AGE       REQUESTOR           CONDITION
csr-f985d   27s       kubelet-bootstrap   Pending
csr-p26bb   1m        kubelet-bootstrap   Pending
csr-z4vz8   13s       kubelet-bootstrap   Pending
[admin@master-1 ~]$ sudo ./local/bin/kubectl certificate approve csr-f985d csr-p26bb csr-z4vz8
certificatesigningrequest "csr-f985d" approved
certificatesigningrequest "csr-p26bb" approved
certificatesigningrequest "csr-z4vz8" approved
```

#### 4、安装dns、dashboard、calico、heapster插件
```
cd /home/admin/k8s-auto-install/scripts/master;
sudo ./install-addons.sh
```

#### 5、验证
```
[admin@master-1 ~]$ sudo ./local/bin/kubectl get pods --all-namespaces -o wide
NAMESPACE     NAME                                        READY     STATUS    RESTARTS   AGE       IP                NODE
kube-system   calico-node-09t5k                           2/2       Running   0          1m        10.12.2.153       master-3
kube-system   calico-node-hv35j                           2/2       Running   0          1m        10.12.2.151       master-1
kube-system   calico-node-smkc9                           2/2       Running   0          1m        10.12.2.152       master-2
kube-system   calico-policy-controller-1746561077-t3d6n   1/1       Running   0          1m        10.12.2.151       master-1
kube-system   heapster-2929994463-h75fd                   1/1       Running   0          1m        192.168.205.193   master-2
kube-system   kube-dns-3119898146-ntt41                   3/3       Running   0          1m        192.168.39.2      master-1
kube-system   kubernetes-dashboard-908585402-722s0        1/1       Running   0          1m        192.168.39.1      master-1
kube-system   monitoring-influxdb-3324367400-x31jr        1/1       Running   0          1m        192.168.39.3      master-1
```
