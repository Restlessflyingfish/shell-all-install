#!/bin/env bash
#kubeadm一键安装(支持一个master节点，2个node)
#使用前提：root用户,有网。有各自ip
#确定k8s集群ip
function defineip(){
read -p "请输入k8s集群的master的宿主机ip: " MASTER_IP
ping -c 3 $MASTER_IP
if  [ $? -eq 0 ];then
	echo -e "\033[32m----master添加成功----\033[0m"
else
	echo -e "\033[31m----master主机ip不对，添加失败,请检查----\033[0m"
	exit 1
fi

read -p "请输入k8s集群的node01的宿主机ip: " NODE01_IP
ping -c 3 $NODE01_IP 
if [ $? -eq 0 ];then
	echo -e "\033[32m----node01添加成功----\033[0m"
else
	echo -e "\033[31m----node01添加失败，请检查ip或者network----\033[0m"
	exit 1
fi

read -p "请输入k8s集群的node02的宿主机ip: " NODE02_IP
ping -c 3 $NODE02_IP
if [ $? -eq 0 ];then
        echo -e "\033[32m----node02添加成功----\033[0m"
else
        echo -e "\033[31m----node02添加失败，请检查ip或者network----\033[0m"
        exit 1
fi

#添加主机到hosts文件解析
MASTER_HOST='k8s-master'   
NODE01_HOST='k8s-node01'
NODE02_HOST='k8s-node02'

cat  <<-EOF > /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
$MASTER_IP    $MASTER_HOST
$NODE01_IP    $NODE01_HOST
$NODE02_IP    $NODE02_HOST
EOF
}
#安装依赖环境
function relyenv(){
yum install  -y   vim  net-tools  wget 
mkdir /etc/yum.repos.d/bak && mv /etc/yum.repos.d/*.repo  /etc/yum.repos.d/bak
cp  /etc/yum.repos.d/bak/*   /etc/yum.repos.d/
wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
yum install  epel-release -y
yum clean all && yum makecache
yum install -y conntrack ipvsadm ipset jq curl sysstat libseccomp iptables vim net-tools 
systemctl stop firewalld && systemctl disable firewalld   #关闭防火墙
sed -i 's/enforcing/disabled/' /etc/selinux/config && setenforce 0  #关闭selinux
swapoff -a   &&   sed -i '/centos-swap/ s/^/#/g' /etc/fstab   #禁用swap
cat > /etc/sysctl.d/k8s.conf <<-EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
#设置持久化日志
mkdir /etc/systemd/journald.conf.d 
cat > /etc/systemd/journald.conf.d/99-prophet.conf <<-EOF
[Journal] 
#持久化保存到磁盘
Storage=persistent
#压缩使用日志格式
Compress=yes
SyncIntervalSec=5m
RateLimitInterval=30s
RateLimitBurst=1000
#最大占用空间 10G
SystemMaxUse=10G
#单日志文件最大 200M
SystemMaxFileSize=200M
#日志保存时间 2周
MaxRetentionSec=2week
#不将日志转发到syslog
ForwardToSyslog=no
EOF
systemctl restart systemd-journald
#开启ipvs前置条件
modprobe br_netfilter
cat > /etc/sysconfig/modules/ipvs.modules <<-EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
EOF
chmod 755 /etc/sysconfig/modules/ipvs.modules 
bash  /etc/sysconfig/modules/ipvs.modules
lsmod  |  grep  -e ip_vs
lsmod  |  grep -e  nf_conntrack_ipv4
}

function upkernel(){
#判断内核有没有更新
uname -a | grep 4.4
if [ $? -eq 0 ];then
	echo -e "\033[32m---内核为4.4版，不必更新内核---\033[0m"
else
	echo -e "\033[32m---内核为3.10，正在更新内核---\033[0m"
	rpm -Uvh  http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
	if [ "$?" -eq 0 ];then
		echo -e "\033[32m---内核更新成功---\033[0m"
	else
		rpm -Uvh  http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
	fi
	yum --enablerepo=elrepo-kernel install -y kernel-lt
	grub2-set-default  'CentOS Linux (4.4.189-1.el7.elrepo.x86_64) 7 (Core)'
fi
}


function relk8s(){
#安装docker
yum install -y yum-utils device-mapper-persistent-data lvm2
wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -O  /etc/yum.repos.d/docker-ce.repo
yum -y install docker-ce
systemctl enable docker && systemctl start docker
docker --version
#配置docker-daemon
mkdir  -p  /etc/docker 
cat > /etc/docker/daemon.json <<-EOF
{
	"registry-mirrors": ["https://mjizpts4.mirror.aliyuncs.com"], 
	"exec-opts":["native.cgroupdriver=systemd"],
	"log-driver": "json-file",
	"log-opts":{
	  "max-size": "100m"
	}
}
EOF
mkdir -p /etc/systemd/system/docker.sercer.d
systemctl daemon-reload && systemctl restart docker

#配置国内阿里云的k8s软件源
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
#安装kubeadm，kubelet和kubectl
yum install -y kubelet-1.18.2  kubeadm-1.18.2  kubectl-1.18.2
systemctl enable kubelet && systemctl start kubelet
}

function k8smaster(){
#部署k8smaster,k8s版本一定要高于kubelet版本
MASTER_HOSTNAME=`cat  /etc/hosts | grep $MASTER_IP  | awk '{print $2}'`
hostnamectl set-hostname  $MASTER_HOSTNAME    &&  echo  $MASTER_HOSTNAME  > /etc/hostname
kubeadm init  --apiserver-advertise-address=$MASTER_IP  --image-repository registry.aliyuncs.com/google_containers   --kubernetes-version v1.18.2 --service-cidr=10.1.0.0/16   --pod-network-cidr=10.244.0.0/16   >  /tmp/k8smaster.ini
#添加master管理k8s集群权限
ADMINCONF=`cat /etc/profile | grep /etc/kubernetes/admin.conf | wc -l`
if [ "$ADMINCONF" -eq "0" ];then
	echo "已经添加master管理k8s集群权限"
else
	cat >> /etc/profile <<-EOF
	export KUBECONFIG=/etc/kubernetes/admin.conf
	EOF
	source /etc/profile
fi
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
}
function flannel(){
#安装flannel
cat > /root/flannel.yaml <<-EOF
---
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: psp.flannel.unprivileged
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: docker/default
    seccomp.security.alpha.kubernetes.io/defaultProfileName: docker/default
    apparmor.security.beta.kubernetes.io/allowedProfileNames: runtime/default
    apparmor.security.beta.kubernetes.io/defaultProfileName: runtime/default
spec:
  privileged: false
  volumes:
    - configMap
    - secret
    - emptyDir
    - hostPath
  allowedHostPaths:
    - pathPrefix: "/etc/cni/net.d"
    - pathPrefix: "/etc/kube-flannel"
    - pathPrefix: "/run/flannel"
  readOnlyRootFilesystem: false
  # Users and groups
  runAsUser:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  fsGroup:
    rule: RunAsAny
  # Privilege Escalation
  allowPrivilegeEscalation: false
  defaultAllowPrivilegeEscalation: false
  # Capabilities
  allowedCapabilities: ['NET_ADMIN']
  defaultAddCapabilities: []
  requiredDropCapabilities: []
  # Host namespaces
  hostPID: false
  hostIPC: false
  hostNetwork: true
  hostPorts:
  - min: 0
    max: 65535
  # SELinux
  seLinux:
    # SELinux is unused in CaaSP
    rule: 'RunAsAny'
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: flannel
rules:
  - apiGroups: ['extensions']
    resources: ['podsecuritypolicies']
    verbs: ['use']
    resourceNames: ['psp.flannel.unprivileged']
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - get
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - nodes/status
    verbs:
      - patch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flannel
  namespace: kube-system
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-flannel-cfg
  namespace: kube-system
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan"
      }
    }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-flannel-ds-amd64
  namespace: kube-system
  labels:
    tier: node
    app: flannel
spec:
  selector:
    matchLabels:
      app: flannel
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: beta.kubernetes.io/os
                    operator: In
                    values:
                      - linux
                  - key: beta.kubernetes.io/arch
                    operator: In
                    values:
                      - amd64
      hostNetwork: true
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni
        image: quay.io/coreos/flannel:v0.12.0-amd64
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: quay.io/coreos/flannel:v0.12.0-amd64
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
            add: ["NET_ADMIN"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      volumes:
        - name: run
          hostPath:
            path: /run/flannel
        - name: cni
          hostPath:
            path: /etc/cni/net.d
        - name: flannel-cfg
          configMap:
            name: kube-flannel-cfg
EOF
cd  /root/ &&  kubectl apply -f  flannel.yaml
}
# 部署master
function masterinstall(){
	#定义ip
	defineip
	#更新内核
	upkernel
	#安装系统依赖的环境变量
	relyenv
	#安装k8s依赖的组件
	relk8s
	#k8s的master节点一键初始化
	k8smaster
	#k8s的flannel网络
	flannel
        echo -n "-------------------------------------------------------------------------"
        echo -e "\033[32m---k8s的master节点以安装完成---\033[0m"
        echo -e "\033[32m---kubectl get  node 查看节点是否Ready---\033[0m"
        echo -e "\033[32m---kubectl get  cs 查看各组件是否健康---\033[0m"
        echo -e "\033[32m---kubectl get pods -n kube-system 查看各pods是否running---\033[0m"
        echo -n "-------------------------------------------------------------------------"
}
# 部署node
function nodeinstall(){
#定义node01
read -p "请输入k8s集群的node01的宿主机ip: " NODE01_IP
ping -c 3 $NODE01_IP
if [ $? -eq 0 ];then
        echo -e "\033[32m----node01添加成功----\033[0m"
else
        echo -e "\033[31m----node01添加失败，请检查ip或者network----\033[0m"
        exit 1
fi
read -p "请输入node01的ssh端口: "  NODE01_SSHPORT
read -p "请输入node01的密码: "     NODE01_PASSWORD
#定义node02
read -p "请输入k8s集群的node02的宿主机ip: " NODE02_IP
ping -c 3 $NODE02_IP
if [ $? -eq 0 ];then
        echo -e "\033[32m----node02添加成功----\033[0m"
else
        echo -e "\033[31m----node02添加失败，请检查ip或者network----\033[0m"
        exit 1
fi
read -p "请输入node02的ssh端口: "  NODE02_SSHPORT
read -p "请输入node02的密码: "     NODE02_PASSWORD

#安装ansible
yum  install ansible  -y 
#ansible加入node主机
echo '[allnode]'  >>  /etc/ansible/hosts
echo "$NODE01_IP  ansible_ssh_port=$NODE01_SSHPORT  ansible_ssh_user=root  ansible_ssh_pass=$NODE01_PASSWORD" >>  /etc/ansible/hosts
echo "$NODE02_IP  ansible_ssh_port=$NODE02_SSHPORT  ansible_ssh_user=root  ansible_ssh_pass=$NODE02_PASSWORD" >>  /etc/ansible/hosts
sed  -i 's/#host_key_checking = False/host_key_checking = False/g'  /etc/ansible/ansible.cfg   #修改为禁止检查key
ansible  allnode  -m  ping
if [ $? -eq 0 ];then
	echo -e "\033[32m---ansible连接成功---\033[0m"
else
	echo -e "\033[31m---ansible连接失败,之前输入的ssh端口或者密码有误，请重新执行并输入---\033[0m"
	exit 1
fi
#更新hostname与hosts文件
ansible allnode -m copy  -a "src=/etc/hosts  dest=/etc/"                       #传输主机hosts信息
NODE01_HOSTNAME=`cat  /etc/hosts | grep $NODE01_IP  | awk '{print $2}'`
ansible $NODE01_IP -m shell -a "hostnamectl set-hostname  $NODE01_HOSTNAME  &&  echo $NODE01_HOSTNAME  > /etc/hostname"
NODE02_HOSTNAME=`cat  /etc/hosts | grep $NODE02_IP  | awk '{print $2}'`
ansible $NODE02_IP -m shell -a "hostnamectl set-hostname  $NODE02_HOSTNAME  &&  echo $NODE02_HOSTNAME  > /etc/hostname"
ansible allnode -m copy  -a "src=/root/kubeadm-install.sh dest=/root/"         #传输安装脚本
ansible allnode -m shell -a "cd /root/ &&  bash kubeadm-install.sh upkernel"
ansible allnode -m shell -a "cd /root/ &&  bash kubeadm-install.sh relyenv"
ansible allnode -m shell -a "cd /root/ &&  bash kubeadm-install.sh relk8s"
#node使用kubeadm join加入k8s集群
KUBEADM_JOIN=`cat  /tmp/k8smaster.ini  | tail -n 2`
ansible allnode -m shell -a  "$KUBEADM_JOIN"  
}
case $1 in 
defineip)
	#定义集群节点ip
	defineip
	;;
upkernel)
	#更新内核
	upkernel
	;;
relyenv)
	#安装k8s系统环境
	relyenv
	;;
relk8s)
	#安装k8s依赖环境
	relk8s
	;;
k8smaster)
	#k8s的master的init
	k8smaster
	;;
flannel)
	flannel
	;;
masterinstall)
	#master节点部署
	masterinstall
	;;	
nodeinstall)
	#node节点部署
	nodeinstall
	;;
*)
	echo    "-------------------------------------------------------------------------------------------------"
	echo -e "\033[31m1.  bash $0 defineip(定义节点ip)|upkernel(更新内核为4.4)|relyenv(安装k8s系统环境)|relk8s(安装k8s相应依赖组件)|k8smaster(k8s的master初始化)|flannel(安装flannel组件)\033[0m"
	echo    "-------------------------------------------------------------------------------------------------"
	echo -e "\033[31m2. bash $0  masterinstall(master节点一键部署)|nodeinstall(node节点一键部署和添加)\033[0m"
	echo    "-------------------------------------------------------------------------------------------------"
	;;
esac
