#!/usr/bin/bash
#shell一键安装各类服务


function  base-env() {
	#stop  firewalld and selinux
	systemctl stop  firewalld
	systemctl disable firewalld
	#stop selinux
	setenforce 0 && sed  -i 's/SELINUX=enforcing/SELINUX=disabled/g'  /etc/selinux/config
	# env check
	if [ $LOGNAME != root ]; then
 	    echo -e  "\033[31m---- 请切换为root用户执行----\033[0m"
     	exit 1
    fi
	ping -c 3 www.baidu.com 
	if [ $? -eq 0 ];then
		echo -e "\033[32m--- network is ok---\033[0m"
	else
		echo -e "\033[32m--- network is faild,please check---\033[0m"
		exit 1
	fi
	# deploy repo
	yum install wget  vim gcc net-tools -y
	yum  install epel-release  -y
	wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
	yum repolist  &&  yum makecache
}

function  mysql-8-install() {
	# 安装依赖组件
	yum  install  wget gcc  vim  libaio libaio* -y 
	MYSQL_EXIST=$(find  / -name mysql.sock  | wc -l)
	MYSQL_BASEDIR="/srv/mysql"
	MYSQL_DATADIR="/srv/mysql/data"
	if [[ "${MYSQL_EXIST}" -eq "0" ]]; then		
		while true
		do 
			wget -c https://mirrors.tuna.tsinghua.edu.cn/mysql/downloads/MySQL-8.0/mysql-8.0.21-linux-glibc2.12-x86_64.tar.xz
	    	if [ $? -eq 0 ];then
				break;
	    	else
				sleep 3
				wget -c https://mirrors.tuna.tsinghua.edu.cn/mysql/downloads/MySQL-8.0/mysql-8.0.21-linux-glibc2.12-x86_64.tar.xz
				break;
	   		fi
		done
		if [ -f "./mysql-8.0.21-linux-glibc2.12-x86_64.tar.xz" ];then 
			echo -e "\033[32m---- mysql package is success----\033[0m"
			mkdir -p $MYSQL_DATADIR
			#解压tar.xz包
			xz -d mysql-8.0.21-linux-glibc2.12-x86_64.tar.xz  
			tar  -xvf  mysql-8.0.21-linux-glibc2.12-x86_64.tar 
			mv mysql-8.0.21-linux-glibc2.12-x86_64  $MYSQL_BASEDIR/mysql-8
			groupadd mysql  &&   useradd -g mysql mysql -s /sbin/nologin   #创建mysql用户
			chown -R mysql:mysql $MYSQL_DATADIR    #创建数据目录并授权
			cp   /etc/my.cnf   /etc/my.cnf.bak
			cat > /etc/my.cnf  <<-EOF
			[client]
			port = 3306
			socket = /var/lib/mysql/mysql.sock
			[mysqld]
			basedir=$MYSQL_BASEDIR
			datadir=$MYSQL_DATADIR
			socket=/var/lib/mysql/mysql.sock
			pid-file=/tmp/mysql.pid
			default-storage-engine = INNODB
			init_connect='SET collation_connection = utf8_unicode_ci'
			init_connect='SET NAMES utf8'
			character-set-server = utf8
			collation-server=utf8_unicode_ci
			skip-character-set-client-handshake
			wait_timeout = 86400000
			interactive_timeout = 86400000
			max_allowed_packet=256M
			innodb_log_file_size=512M
			max_connections=10000
			symbolic-links=0
			[mysqld_safe]
			log-error=/var/log/mysql/error.log
			pid-file=/var/log/mysql/mysqld.pid
			!includedir /etc/my.cnf.d
			EOF
		else
			echo -e "\033[31m---mysql-8.0.21 download faild,please check network---\033[0m"
			exit 1
		fi  
		#初始化数据库
		/srv/mysql/mysql-8/bin/mysqld   --initialize-insecure  --user=mysql --basedir=$MYSQL_BASEDIR  --datadir=$MYSQL_DATADIR   #初始化数据库，记录密初始化密码
		mkdir -p /var/lib/mysql/   &&   chown -R   mysql:mysql   /var/lib/mysql/
		mkdir -p /var/log/mysql/   &&  touch   /var/log/mysql/error.log  &&  chown -R   mysql:mysql   /var/log/mysql/
		ln -s /srv/mysql/mysql-8/bin/*  /usr/bin/
		ln -s  /var/lib/mysql/mysql.sock  /tmp/mysql.sock
	else
		echo -e "\033[31m---mysql is exists---\033[0m"
		exit 1
	fi
	#start  mysql
	MYSQL_PORT=`ss -anlt | grep 3306 | wc -l`
	if [ $MYSQL_PORT -eq 0 ];then
    	nohup /srv/mysql/mysql-8/bin/mysqld_safe  &      #start  mysql
    	echo -e "mysql is start success"
    else
    	echo -e "\033[31m--- mysql端口被其它程序占用,请手动修改配置文件的端口再启动---\033[0m"
    fi
	echo -e '-----------------------------------------------------------------------------------'  >> $MYSQL_BASEDIR/mysql-install.out
	echo -e "\033[32m--mysql-8  is  successful----------\033[0m"	 >> $MYSQL_BASEDIR/mysql-install.out
	echo -e '\033[32m--mysql的basedir=/srv/mysql/--------\033[0m'  >> $MYSQL_BASEDIR/mysql-install.out
	echo -e '\033[32m--mysql的datadir=/srv/mysql/data-----\033[0m'  >> $MYSQL_BASEDIR/mysql-install.out
	echo -e '默认无密码,可使用该语句强制修改密码ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'PASSWORD' PASSWORD EXPIRE NEVER ;'  >> $MYSQL_BASEDIR/mysql-install.out
	echo -e '---------------------------------------------------------------------------------------'  >> $MYSQL_BASEDIR/mysql-install.out
	#mysql -uroot -ppassword  
	#第一次登入如果会提示修改密码，使用该语句修改
	#alter user 'root'@'localhost' identified by 'k8sk8s';
}

function  redis-5-install() {
	#安装基础依赖
	REDIS_BASEDIR="/srv/redis-5"
	REDIS_CONF="/srv/redis"
	REDIS_DATADIR="/var/lib/redis"
	REDIS_LOGDIR="/var/log/redis"
	yum  install  wget vim gcc -y
	while true
	do 
		wget -c https://download.redis.io/releases/redis-5.0.10.tar.gz?_ga=2.86071581.48191840.1604647353-537086586.1604647353
	    if [ $? -eq 0 ];then
			break;
	    else
			sleep 3
			wget -c https://download.redis.io/releases/redis-5.0.10.tar.gz?_ga=2.86071581.48191840.1604647353-537086586.1604647353
			break;
	   fi
	done
	if [ -f "./redis-5.0.10.tar.gz?_ga=2.86071581.48191840.1604647353-537086586.1604647353" ];then 
		echo -e "\033[32m---- redis package is success----\033[0m"
	else
		echo -e "\033[31m---- redis package is failed----\033[0m"
		exit 1
	fi
	tar  -zxvf  redis-5.0.10.tar.gz?_ga=2.86071581.48191840.1604647353-537086586.1604647353
	mv redis-5.0.10   $REDIS_BASEDIR
	cd  $REDIS_BASEDIR      &&  make -j 3    &&  make  install 
	ln -s  $REDIS_BASEDIR/src/redis-*  /usr/bin/
	mkdir  $REDIS_CONF   &&   cp  $REDIS_BASEDIR/redis.conf   $REDIS_CONF/6379.conf
	mkdir -p  $REDIS_DATADIR    &&  mkdir  -p  $REDIS_LOGDIR
	cat > $REDIS_CONF/6379.conf <<-EOF
	protected-mode yes
	port 6379
	tcp-backlog 511
	timeout 0
	tcp-keepalive 300
	daemonize yes
	supervised no
	pidfile /var/run/redis_6379.pid
	loglevel notice
	logfile $REDIS_LOGDIR/redis.log
	databases 16
	save 900 1
	save 300 10
	save 60 10000
	stop-writes-on-bgsave-error yes
	rdbcompression yes
	rdbchecksum yes
	dbfilename dump.rdb
	dir $REDIS_DATADIR
	slave-serve-stale-data yes
	slave-read-only yes
	repl-diskless-sync no
	repl-diskless-sync-delay 5
	repl-disable-tcp-nodelay no
	slave-priority 100
	requirepass sz-redis
	appendonly no
	appendfilename "appendonly.aof"
	appendfsync everysec
	no-appendfsync-on-rewrite no
	auto-aof-rewrite-percentage 100
	auto-aof-rewrite-min-size 64mb
	aof-load-truncated yes
	lua-time-limit 5000
	slowlog-log-slower-than 10000
	slowlog-max-len 128
	latency-monitor-threshold 0
	notify-keyspace-events ""
	hash-max-ziplist-entries 512
	hash-max-ziplist-value 64
	list-max-ziplist-size -2
	list-compress-depth 0
	set-max-intset-entries 512
	zset-max-ziplist-entries 128
	zset-max-ziplist-value 64
	hll-sparse-max-bytes 3000
	activerehashing yes
	client-output-buffer-limit normal 0 0 0
	client-output-buffer-limit slave 256mb 64mb 60
	client-output-buffer-limit pubsub 32mb 8mb 60
	hz 10
	aof-rewrite-incremental-fsync yes
	EOF
    REDIS_PORT=`ss -anlt | grep 6379 | wc -l`
    if [ $REDIS_PORT -eq 0 ];then
    	redis-server       $REDIS_CONF/6379.conf      #启动redis
    	echo -e "redis is start success"
    else
    	echo -e "\033[31m--- redis端口被其它程序占用,请手动修改配置文件的端口再启动---\033[0m"
    fi
	echo -e "--------------------------------------------------------------------"  >> $REDIS_BASEDIR/redis-install.out
    echo -e "\033[32m-----redis  is  successful-----\033[0m"    >> $REDIS_BASEDIR/redis-install.out
    echo -e "\033[32m-----安装路径：  $REDIS_BASEDIR-----\033[0m"  >> $REDIS_BASEDIR/redis-install.out
    echo -e "\033[32m-----配置路径：  $REDIS_CONF -----\033[0m"   >> $REDIS_BASEDIR/redis-install.out
    echo -e "\033[32m-----数据路径：  $REDIS_DATADIR-----\033[0m"  >> $REDIS_BASEDIR/redis-install.out
    echo -e "\033[32m-----日志路径：  $REDIS_LOGDIR-----\033[0m"  >> $REDIS_BASEDIR/redis-install.out
    echo -e "\033[32m-----port： 6379  password: sz-redis -----\033[0m"  >> $REDIS_BASEDIR/redis-install.out
    echo -e " 启动命令：  redis-server   $REDIS_CONF/6379.conf"  >> $REDIS_BASEDIR/redis-install.out
    echo -e "---------------------------------------------------------------------"  >> $REDIS_BASEDIR/redis-install.out
}

function mongodb-4-install () {
    MONGODB_BASEDIR="/srv/mongodb-4"
    MONGODB_DATADIR="/srv/mongodb-4/data"
    MONGODB_ERROR_LOG="/srv/mongodb-4/log/"
    yum install -y libcurl openssl  wget #依赖包安装
	while true
	do 
		wget -c https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-rhel70-4.2.10.tgz
	    if [ $? -eq 0 ];then
			break;
	    else
			sleep 3
			wget -c https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-rhel70-4.2.10.tgz
			break;
	   fi
	done
	if [ -f "./mongodb-linux-x86_64-rhel70-4.2.10.tgz" ];then 
		echo -e "\033[32m---- mongodb package is success----\033[0m"
	else
		echo -e "\033[31m---- mongodb package is failed----\033[0m"
		exit 1
	fi
    #创建对应目录
    mkdir -p  $MONGODB_BASEDIR  
    mkdir -p  $MONGODB_DATADIR
    mkdir -p  $MONGODB_ERROR_LOG
    tar  -zxvf mongodb-linux-x86_64-rhel70-4.2.10.tgz  -C /root
    \mv /root/mongodb-linux-x86_64-rhel70-4.2.10 $MONGODB_BASEDIR/mongodb
    cat > /etc/mongodb.conf <<-EOF
	# mongod.conf
	# for documentation of all options, see:
	# http://docs.mongodb.org/manual/reference/configuration-options/
	# where to write logging data.
	systemLog:
	   destination: file
	   logAppend: true
	   path: $MONGODB_ERROR_LOG/mongo.log
	# Where and how to store data.
	storage:
	   dbPath: $MONGODB_DATADIR
	   journal:
	     enabled: true
	#  engine:
	#  wiredTiger:
	#  how the process runs
	processManagement:
	   fork: true  # fork and run in background
	   pidFilePath: $MONGODB_BASEDIR/mongod.pid  # location of pidfile
	   timeZoneInfo: /usr/share/zoneinfo
	#  network interfaces
	net:
	   port: 27017
	   bindIp: 0.0.0.0  # Enter 0.0.0.0,:: to bind to all IPv4 and IPv6 addresses or, alternatively, use the net.bindIpAll setting.
	EOF
    ln  -s  $MONGODB_BASEDIR/mongodb/bin/*  /usr/bin/   #添加环境变量
    MONGO_PORT=`ss -anlt | grep 27017 | wc -l`
    if [ $MONGO_PORT -eq 0 ];then
    	mongod  -f  /etc/mongodb.conf   #启动mongo
    	echo -e "mongo is start success"
    else
    	echo -e "\033[31m--- mongo端口被其它程序占用,请手动修改配置文件的端口再启动---\033[0m"
    fi
    	echo -e "--------------------------------------------------------------------"  >>   $MONGODB_BASEDIR/mongodb-install.out
    	echo -e "\033[32m-----mongodb is  successful-----\033[0m"      >>   $MONGODB_BASEDIR/mongodb-install.out
    	echo -e "\033[32m-----安装路径：  /srv/mongodb-4/-----\033[0m"   >>   $MONGODB_BASEDIR/mongodb-install.out
    	echo -e "\033[32m-----数据文件路径：/srv/mongodb-4/data/-----\033[0m"  >>   $MONGODB_BASEDIR/mongodb-install.out
    	echo -e "\033[32m-----错误日志路径：/srv/mongodb-4/log/mongodb.log-----\033[0m"  >>   $MONGODB_BASEDIR/mongodb-install.out
    	echo -e "\033[32m-----访问ip：  http://localhost:27017/-----\033[0m"  >>   $MONGODB_BASEDIR/mongodb-install.out
    	echo -e "启动命令： mongod  -f  /etc/mongodb.conf "   >>   $MONGODB_BASEDIR/mongodb-install.out
    	echo -e "关闭命令： mongod --shutdown  -f /etc/mongodb.conf "  >>   $MONGODB_BASEDIR/mongodb-install.out
    	echo -e "---------------------------------------------------------------------"  >>   $MONGODB_BASEDIR/mongodb-install.out
}


function elasticsearch-7-install() {
	#判断java是否安装
	java -version
	if [ $? -eq 0 ];then
		echo  "java env is success"
	else
		yum install java -y
	fi
	#安装elasticsearch7.1
	ES_EXISTS=`rpm -qa | grep elasticsearch | wc -l`
	if [ $ES_EXISTS -eq 0 ];then		
		cat > /etc/yum.repos.d/elasticsearch.repo <<-EOF
		[elasticsearch]
		name=Elasticsearch repository for 7.x packages
		baseurl=https://artifacts.elastic.co/packages/7.x/yum
		gpgcheck=1
		gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
		enabled=0
		autorefresh=1
		type=rpm-md
		EOF
		rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
		yum install elasticsearch-7.1.1 --enablerepo=elasticsearch  -y 
		sed -i 's/#node.name: node-1/node.name: es-node1/g'  /etc/elasticsearch/elasticsearch.yml
		sed -i 's/#network.host: 192.168.0.1/network.host: 0.0.0.0/g'  /etc/elasticsearch/elasticsearch.yml
		sed -i 's/#cluster.initial_master_nodes: \["node-1", "node-2"\]/cluster.initial_master_nodes: \["es-node1"\]/g'  /etc/elasticsearch/elasticsearch.yml
		ES_PORT=`ss   -anlt | grep 9[2-3]00 | wc -l`
		if [ "$ES_PORT" -eq 0 ];then
			systemctl enable elasticsearch
	    	systemctl restart elasticsearch
	    	systemctl status elasticsearch
	    else
	    	echo -e "\033[31m--- es-7已经安装完毕,但是9200 端口已被其它程序占用,请修改配置文件在手动启动 ---"
	    	exit 1
	    fi
	    echo -e "--------------------------------------------------------------------"
    	echo -e "\033[32m----- elasticsearch-7 is  successful-----\033[0m"
    	echo -e "\033[32m----- elasticsearch-7 配置文件: /etc/elasticsearch/elasticsearch.yml-------\033[0m"
    	echo -e "\033[32m----- 访问方式: http://ip:9200-----\033[0m"
    	echo -e "-----------------------------------------------------------------------"

    else
    	echo -e "\033[31m----- elasticsearch-7 is exists -----\033[0m"
    	exit 1
    fi
}

function  python-3-install() {
	#判断python3是否存在
	python3 -V
	if [ $? -eq 0 ];then
		echo -e "\033[31m--- python3 env is exists ---\033[0m"
		exit 1
	else
		#在线安装依赖
		yum install wget openssl-devel bzip2-devel expat-devel gdbm-devel readline-devel sqlite-devel gcc gcc-c++ -y 
		#编译安装python3.6.8
		while true
		do 
			wget -c https://www.python.org/ftp/python/3.6.8/Python-3.6.8.tgz
	    	if [ $? -eq 0 ];then
				break;
	    	else
				sleep 3
				wget -c https://www.python.org/ftp/python/3.6.8/Python-3.6.8.tgz
				break;
	   		fi
		done
		if [ -f "./Python-3.6.8.tgz" ];then 
			echo -e "\033[32m---- python3 package is success----\033[0m"
		else
			echo -e "\033[31m---- python3 package is failed----\033[0m"
			exit 1
		fi
		mv Python-3.6.8.tgz /usr/local/src
		cd /usr/local/src
		tar -xzvf Python-3.6.8.tgz
		cd Python-3.6.8  &&  ./configure prefix=/usr/local/python3 --enable-optimizations --with-ssl   &&  make  -j 4   &&   make  install 
		ln -s /usr/local/python3/bin/python3 /usr/bin/python3
		ln -s /usr/local/python3/bin/pip3   /usr/bin/pip3
		pip install --upgrade pip  #升级pip
	fi
	python3 -V
	if [ $? -eq 0 ];then
		echo -e "--------------------------------------------------------"
		echo -e "\033[32m--- python3 env is install  success ---\033[0m"
		echo -e "\033[32m--- 安装路径为: /usr/local/python3/-----\033[0m"
		echo -e "\033[32m--- python3 and  pip3 均为python 3.6.8版本---\033[0m"
		echo -e "--------------------------------------------------------"
	else
		echo -e "\033[32m--- python3 env is install  failed ---\033[0m"
	fi
}

function  docke-19-install() {
	#采用docker安装启动
	#安装docker-ce
	docker version
	if [ $? -eq 0 ];then
		echo -e "\033[31m--- docker is exists ---\033[0m"
		docker version
	else
		yum install -y yum-utils device-mapper-persistent-data lvm2  git
		yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
		yum makecache fast
		yum -y install docker-ce
		systemctl  start docker  &&  systemctl  enable  docker
		cat > /etc/docker/daemon.json <<-EOF
		{
	  		"registry-mirrors": ["https://mjizpts4.mirror.aliyuncs.com"],
	  		"exec-opts": ["native.cgroupdriver=systemd"],
	  		"log-driver": "json-file",
	  		"log-opts": {
	    	"max-size": "100m"
	  		},
	  		"storage-driver": "overlay2",
	  		"storage-opts": [
	   		"overlay2.override_kernel_check=true"
	  		]
		}
		EOF
		systemctl daemon-reload
		systemctl restart docker
	fi
	echo    "----------------------------------------------------------------"
	#安装docker-compose	
	docker-compose  version
	if [ $? -eq 0 ];then
		echo -e "\033[32m-----docker-compose is exists----\033[0m"
		docker-compose  version
	else
		#安装docker-compose
		curl -L https://get.daocloud.io/docker/compose/releases/download/1.27.4/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
	    chmod +x /usr/local/bin/docker-compose
	fi
}

function nacos-install() {
	#采用docker安装启动
	docke-19-install
	#安装nacos,参考地址https://nacos.io/zh-cn/docs/quick-start-docker.html (集群模式内存大于2G)
	NACOS_BASEDIR="/srv/nacos"
	mkdir  $NACOS_BASEDIR  
	cd  $NACOS_BASEDIR   &&  git clone https://github.com/nacos-group/nacos-docker.git
	echo -e "--------------------------------------------------------------------"   >>  $NACOS_BASEDIR/nacos-install.out
    echo -e "\033[32m----- nacos is  successful-----\033[0m"  >>  $NACOS_BASEDIR/nacos-install.out
    echo -e "\033[32m----- nacos docker-compose文件位置$NACOS_BASEDIR-------\033[0m"  >>  $NACOS_BASEDIR/nacos-install.out
    echo -e "\033[32m----- nacos 为3节点集群模式----------\033[0m"   >>  $NACOS_BASEDIR/nacos-install.out
    echo -e "\033[32m----- nacos 启动命令： cd  $NACOS_BASEDIR/nacos-docker   &&  docker-compose -f example/cluster-hostname.yaml up  -d----------\033[0m"   >>  $NACOS_BASEDIR/nacos-install.out
    echo -e "\033[32m-----访问方式： http://ip:8848/nacos/-----\033[0m"  >>  $NACOS_BASEDIR/nacos-install.out
    echo -e "\033[32m-----登入账号密码： nacos/nacos-----\033[0m"   >>  $NACOS_BASEDIR/nacos-install.out
    echo -e  "\033[31m----如果无法访问最大可能可用内存小于2G----\033[0m"   >>  $NACOS_BASEDIR/nacos-install.out
    echo -e "---------------------------------------------------------------------"  >>  $NACOS_BASEDIR/nacos-install.out
}

function  minio-install() {
	docke-19-install
	#安装minio
	MINIO_BASEDIR="/srv/minio"
	MINIO_DATADIR="/srv/minio/data"
	mkdir -p $MINIO_DATADIR
	cat > $MINIO_BASEDIR/docker-compose.yml <<-EOF
	version: '3.5'
	services:
	  minio:
	    image: minio/minio
	    restart: always
	    container_name: minio
	    volumes:
	      - $MINIO_DATADIR:/data
	    environment:
	      - MINIO_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE
	      - MINIO_SECRET_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
	    ports:
	      - 9000:9000
	    networks:
	      - ii-swarm-net
	    command: ["server", "/data"]
	networks:
	  ii-swarm-net:
	    external: false
	EOF
	echo -e "----------------------------------------------------------------------"
    echo -e "\033[32m----- minio的docker-compose文件存在于$MINIO_BASEDIR-----\033[0m"
    echo -e "-----------------------------------------------------------------------"
	# 启动服务
	# docker-compose up -d
	# 查看服务状态
	# docker-compose ps
}

#k8s使用kubeadm一键安装

function k8s-install() {
	yum install git  -y
	git clone https://github.com/Restlessflyingfish/shell-all-install.git
	mv ./shell-all-install/   /root/k8s-install
	cd /root/k8s-install  &&   chmod +x  kubeadm-install.sh
}

function helm3-install() {
	if helm version || helm3 version;then
		echo -e "\033[32m---helm3 is  exists ---\033[0m"
	else
		cd /opt && wget -c https://get.helm.sh/helm-v3.4.1-linux-amd64.tar.gz
		tar -xvf helm-v3.4.1-linux-amd64.tar.gz
		mv linux-amd64 helm3
		mv helm3/helm helm3/helm3
		chown root.root helm3 -R
		ln -s /opt/helm3/helm3 /usr/bin/helm
		helm init
		helm repo add apphub https://apphub.aliyuncs.com
		helm repo add elastic  	https://helm.elastic.co
		helm repo add traefik  	https://containous.github.io/traefik-helm-chart
		helm repo add kong     	https://charts.konghq.com
		helm repo add bitnami  	https://charts.bitnami.com/bitnami
		helm repo add azure    	http://mirror.azure.cn/kubernetes/charts
		helm repo add aliyun https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts
		helm  repo update  &&  helm  repo  list
		if [ $? -eq 0 ];then
			echo -e "\033[32m---helm3安装成功，已添加ali源---\033[0m"
		else
			echo -e "\033[31m---helm3安装失败，please check---\033[0m"
		fi
	fi
}

function  mongodb-4-k8s() {
        mkdir /opt/
        wget  -c https://github.com/Restlessflyingfish/shell-all-install/archive/main.zip
        yum install unzip -y
        unzip main.zip -d /tmp/
        if [ -d /opt/mongodb ];then
                echo -e "\033[31m---/opt/mongodb directory is  exists!!!---\033[0m"
        else
            cd /tmp/shell-all-install-main && tar -zxvf  mongodb.tar.gz -C /opt/
            echo -e "\033[32m---mongodb is download /opt/,please look---\033[0m"
            rm -f main.zip &&  rm -rf /tmp/shell-all-install-main
        fi
}

function  mysql-8-k8s() {
        mkdir /opt/
        wget  -c https://github.com/Restlessflyingfish/shell-all-install/archive/main.zip
        yum install unzip -y
        unzip main.zip -d /tmp/
        if [ -d /opt/mysql8 ];then
                echo -e "\033[31m---/opt/mysql8 directory is  exists!!!---\033[0m"
        else
            cd /tmp/shell-all-install-main && tar -zxvf  mysql8.tar.gz -C /opt/
            echo -e "\033[32m---mysql8 is download /opt/,please look---\033[0m"
            rm -f main.zip &&  rm -rf /tmp/shell-all-install-main
        fi
}

function  nacos-k8s() {
        mkdir /opt/
        wget  -c https://github.com/Restlessflyingfish/shell-all-install/archive/main.zip
        yum install unzip -y
        unzip main.zip -d /tmp/
        if [ -d /opt/nacos ];then
                echo -e "\033[31m---/opt/nacos directory is  exists!!!---\033[0m"
        else
            cd /tmp/shell-all-install-main && tar -zxvf  nacos.tar.gz -C /opt/
            echo -e "\033[32m---nacos is download /opt/,please look---\033[0m"
            rm -f main.zip &&  rm -rf /tmp/shell-all-install-main
        fi
}

function  redis-5-k8s() {
        mkdir /opt/
        wget  -c https://github.com/Restlessflyingfish/shell-all-install/archive/main.zip
        yum install unzip -y
        unzip main.zip -d /tmp/
        if [ -d /opt/redis ];then
                echo -e "\033[31m---/opt/redis directory is  exists!!!---\033[0m"
        else
            cd /tmp/shell-all-install-main && tar -zxvf  redis.tar.gz -C /opt/
            echo -e "\033[32m---redis is download /opt/,please look---\033[0m"
            rm -f main.zip &&  rm -rf /tmp/shell-all-install-main
        fi
}


#菜单栏
#base-env 基础环境检查（防火墙,selinux,network,执行用户）
#mysql-8-install mysql8.0二进制安装
#redis-5-install  redis5 编译安装
#mongodb-4-install  mongodb4 编译安装
#elasticsearch-7-install  es7 rpm方式安装
#python-3-install   python3 环境安装
#docke-19-install docker-ce 19.0.3环境安装
#nacos-install  docker-compose方式部署
#minio-install  docker-compose方式部署
#k8s-install   kubeadm方式部署 （外置安装法）
# helm3 安装

echo -e "\033[33m---------------------------\033[0m"
echo -e "\033[33m---------------------------\033[0m"
echo -e "          使用须知"
echo -e " 该脚本使用环境为Centos 7版本,"
echo -e "执行用户必须为root,而且必须联网。"
echo -e "  _linux结尾的为单节点安装"
echo -e "_docker结尾的为docker启动"
echo -e "k8s结尾为k8s部署"
echo -e "\033[33m----------------------------\033[0m"
echo -e "\033[33m----------------------------\033[0m"

while true; do
    select input in env_check_linux mysql_8_linux redis_5_linux mongodb_4_linux elasticsearch_7_linux python_3_linux docker_19_install nacos_latest_docker_compose minio_latest_docker_compose k8s-install helm3-install mongodb-4-k8s mysql-8-k8s nacos-k8s redis-5-k8s quit; do
        case $input in
            env_check_linux)
                #环境检查（会关闭selinux,firewalld需要手动关闭）
                echo "---------------------------------------"
                base-env
                echo "---------------------------------------"
                break
                ;;
            mysql_8_linux)
                #mysql8.0二进制安装
                echo "---------------------------------------"
                base-env
                mysql-8-install
                echo "---------------------------------------"
                break
                ;;
            redis_5_linux)
                #redis-5.0编译安装
                echo "---------------------------------------"
                base-env
                redis-5-install
                echo "---------------------------------------"
                break
                ;;
            mongodb_4_linux)
                #mongodb-4 编译安装
                echo "---------------------------------------"
                base-env
                mongodb-4-install
                echo "---------------------------------------"
				break
                ;;
            elasticsearch_7_linux)
                #es 7 版本编译安装
                echo "---------------------------------------"
                base-env
                elasticsearch-7-install
                echo "---------------------------------------"
                break
                ;;
            python_3_linux)
                #python3 环境安装
                echo "---------------------------------------"
                base-env
                python-3-install
                echo "---------------------------------------"
                ;;
            docker_19_install)
                #docker-ce19.03安装
                echo "---------------------------------------"
                docke-19-install
                echo "---------------------------------------"
                break
                ;;
            nacos_latest_docker_compose)
                #nacos使用docker-compose方式部署
                echo "---------------------------------------"
                nacos-install
                echo "---------------------------------------"
                break
                ;;
            minio_latest_docker_compose)
                #minio使用docke-compose方式部署
                echo "---------------------------------------"
                minio-install
                echo "---------------------------------------"
                break
                ;;
            k8s-install)
                #k8s-install使用kubeadm安装部署
                echo "---------------------------------------"
                k8s-install
                mv /root/k8s-install/kubeadm-install.sh  /root/
                rm -rf  /root/k8s-install/
                echo -e "\033[32m---k8s的kubeadm一键安装脚本已经在/root/下生成,请另外执行该脚本bash /root/k8s-install.sh---\033[0m"
                echo "---------------------------------------"
                exit 0
                ;;
            helm3-install)
				#helm3 install
				echo "---------------------------------------"
				helm3-install
				echo -e "\033[32m---helm3安装目录为/opt/helm3/---\033[0m"
				echo "---------------------------------------"
				;;
			mongodb-4-k8s)
				#mongodb-4-k8s k8s yml安装mongodb4.2
				echo "---------------------------------------"
				mongodb-4-k8s
				echo "---------------------------------------"
				;;
			mysql-8-k8s)
				#mysql-8-k8s k8s yml安装mysql8.0
				echo "---------------------------------------"
				mysql-8-k8s
				echo "---------------------------------------"
				;;	
			nacos-k8s)
				#nacos-k8s k8s yml安装nacos
				echo "---------------------------------------"
				nacos-k8s
				echo "---------------------------------------"
				;;
			redis-5-k8s)
				#redis-5-k8s k8s yml安装redis5.2
				echo "---------------------------------------"
				redis-5-k8s
				echo "---------------------------------------"
				;;											
            quit)
                exit 0
                ;;
               *)
                echo "---------------------------------------"
                echo "Please enter the number." 
                echo "---------------------------------------"
                break
                ;;
        esac
    done
done
