#!/bin/bash -i
#

#source the AWS ParallelCluster profile
. /etc/parallelcluster/cfnconfig
touch /home/centos/idio.txt
echo ${cfn_cluster_user} >> /home/centos/idio.txt
systemctl enable --now docker

case "${cfn_cluster_user}" in
	ec2-user)
		yum -y install docker
		service docker start
		chkconfig docker on
		usermod -a -G docker $cfn_cluster_user

##to be replaced with yum -y install docker-compose as the repository problem is fixed
		curl -L "https://github.com/docker/compose/releases/download/1.28.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
		chmod +x /usr/local/bin/docker-compose
	;;
	
	centos)
		version=$(rpm --eval %{centos_ver})
		echo ${version} >> /home/centos/idio.txt
		case "${version}" in
		8)
			dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
			dnf install docker-ce --nobest -y
			systemctl enable --now docker
			usermod -a -G docker $cfn_cluster_user
			echo "middle docker" >> /home/centos/idio.txt
			curl -L https://github.com/docker/compose/releases/download/1.28.5/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
			chmod +x /usr/local/bin/docker-compose
			echo "end docker" >> /home/centos/idio.txt

		;;
		7)
			yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
			yum install docker-ce docker-ce-cli containerd.io -y
			systemctl start docker
			usermod -a -G docker $cfn_cluster_user
			curl -L https://github.com/docker/compose/releases/download/1.28.5/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
			chmod +x /usr/local/bin/docker-compose
		;;
		esac
	;;
esac

monitoring_dir_name=$(echo ${cfn_postinstall_args}| cut -d ',' -f 2 )
monitoring_home="/home/${cfn_cluster_user}/${monitoring_dir_name}"

echo ${monitoring_dir_name} >> /home/centos/idio.txt
echo ${monitoring_home} >> /home/centos/idio.txt

case "${cfn_node_type}" in
	MasterServer)
		touch /home/centos/tonto.txt
		#cfn_efs=$(cat /etc/chef/dna.json | grep \"cfn_efs\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		#cfn_cluster_cw_logging_enabled=$(cat /etc/chef/dna.json | grep \"cfn_cluster_cw_logging_enabled\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cfn_fsx_fs_id=$(cat /etc/chef/dna.json | grep \"cfn_fsx_fs_id\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		master_instance_id=$(ec2-metadata -i | awk '{print $2}')
		cfn_max_queue_size=$(aws cloudformation describe-stacks --stack-name $stack_name --region $cfn_region | jq -r '.Stacks[0].Parameters | map(select(.ParameterKey == "MaxSize"))[0].ParameterValue')
		s3_bucket=$(echo $cfn_postinstall | sed "s/s3:\/\///g;s/\/.*//")
		cluster_s3_bucket=$(cat /etc/chef/dna.json | grep \"cluster_s3_bucket\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cluster_config_s3_key=$(cat /etc/chef/dna.json | grep \"cluster_config_s3_key\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cluster_config_version=$(cat /etc/chef/dna.json | grep \"cluster_config_version\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		log_group_names="\/aws\/parallelcluster\/$(echo ${stack_name} | cut -d "-" -f2-)"
		echo "midlle1 " >> /home/centos/tonto.txt
		echo ${cfn_fsx_fs_id} >> /home/centos/tonto.txt
		echo ${master_instance_id} >> /home/centos/tonto.txt
		echo ${cfn_max_queue_size} >> /home/centos/tonto.txt
		echo ${s3_bucket} >> /home/centos/tonto.txt
		echo ${cluster_s3_bucket} >> /home/centos/tonto.txt
		echo ${cluster_config_s3_key} >> /home/centos/tonto.txt
		echo ${cluster_config_version} >> /home/centos/tonto.txt
		echo ${log_group_names} >> /home/centos/tonto.txt
		echo "" >> /home/centos/tonto.txt
		aws s3api get-object --bucket $cluster_s3_bucket --key $cluster_config_s3_key --region $cfn_region --version-id $cluster_config_version ${monitoring_home}/parallelcluster-setup/cluster-config.json

		yum -y install golang-bin 

		chown $cfn_cluster_user:$cfn_cluster_user -R /home/$cfn_cluster_user
		chmod +x ${monitoring_home}/custom-metrics/* 

		cp -rp ${monitoring_home}/custom-metrics/* /usr/local/bin/
		mv ${monitoring_home}/prometheus-slurm-exporter/slurm_exporter.service /etc/systemd/system/

	 	(crontab -l -u $cfn_cluster_user; echo "*/1 * * * * /usr/local/bin/1m-cost-metrics.sh") | crontab -u $cfn_cluster_user -
		(crontab -l -u $cfn_cluster_user; echo "*/60 * * * * /usr/local/bin/1h-cost-metrics.sh") | crontab -u $cfn_cluster_user - 

#		echo "midlle2 " >> /home/centos/tonto.txt
		# replace tokens 
		sed -i "s/_S3_BUCKET_/${s3_bucket}/g"               	${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/ParallelCluster.json 
		sed -i "s/__FSX_ID__/${cfn_fsx_fs_id}/g"            	${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__AWS_REGION__/${cfn_region}/g"           	${monitoring_home}/grafana/dashboards/ParallelCluster.json 

		sed -i "s/__AWS_REGION__/${cfn_region}/g"           	${monitoring_home}/grafana/dashboards/logs.json
		sed -i "s/__LOG_GROUP__NAMES__/${log_group_names}/g"    ${monitoring_home}/grafana/dashboards/logs.json

		sed -i "s/__Application__/${stack_name}/g"          	${monitoring_home}/prometheus/prometheus.yml 

		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/master-node-details.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/compute-node-list.json 
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/compute-node-details.json 

		sed -i "s/__MONITORING_DIR__/${monitoring_dir_name}/g"  ${monitoring_home}/docker-compose/docker-compose.master.yml

		#Generate selfsigned certificate for Nginx over ssl
		nginx_dir="${monitoring_home}/nginx"
		nginx_ssl_dir="${nginx_dir}/ssl"
		mkdir -p ${nginx_ssl_dir}
		echo -e "\nDNS.1=$(ec2-metadata -p | awk '{print $2}')" >> "${nginx_dir}/openssl.cnf"
#		openssl req -new -x509 -nodes -newkey rsa:4096 -days 3650 -keyout "${nginx_ssl_dir}/nginx.key" -out "${nginx_ssl_dir}/nginx.crt" -config "${nginx_dir}/openssl.cnf"

		#give $cfn_cluster_user ownership 
		chown -R $cfn_cluster_user:$cfn_cluster_user "${nginx_ssl_dir}/nginx.key"
		chown -R $cfn_cluster_user:$cfn_cluster_user "${nginx_ssl_dir}/nginx.crt"

#		/usr/local/bin/docker-compose --env-file /etc/parallelcluster/cfnconfig -f ${monitoring_home}/docker-compose/docker-compose.master.yml -p monitoring-master up -d

		# Download and build prometheus-slurm-exporter 
		##### Plese note this software package is under GPLv3 License #####
		# More info here: https://github.com/vpenso/prometheus-slurm-exporter/blob/master/LICENSE
		cd ${monitoring_home}
		git clone https://github.com/vpenso/prometheus-slurm-exporter.git
#		cd prometheus-slurm-exporter
#		GOPATH=/root/go-modules-cache HOME=/root go mod download
#		GOPATH=/root/go-modules-cache HOME=/root go build
#		mv ${monitoring_home}/prometheus-slurm-exporter/prometheus-slurm-exporter /usr/bin/prometheus-slurm-exporter
		echo "midlle3 " >> /home/centos/tonto.txt
#		systemctl daemon-reload
#		systemctl enable slurm_exporter
#		systemctl start slurm_exporter
		echo "END " >> /home/centos/tonto.txt
	;;

	ComputeFleet)
		compute_instance_type=$(ec2-metadata -t | awk '{print $2}')
#		gpu_instances="[pg][2-9].*\.[0-9]*[x]*large"
		touch /home/centos/III.txt
		echo $compute_instance_type >> /home/centos/III.txt
#		echo $compute_instance_type >> /home/centos/III.txt
#		if [[ $compute_instance_type =~ $gpu_instances ]]; then
#			distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
#			curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | tee /etc/yum.repos.d/nvidia-docker.repo
#			if [[${cfn_cluster_user} == centos]] && [[${version} == 8]]; then
#				dnf -y clean expire-cache
#				dnf -y install nvidia-docker2
#			else
#				yum -y clean expire-cache
#				yum -y install nvidia-docker2
#			fi
#			systemctl restart docker
#			/usr/local/bin/docker-compose -f /home/${cfn_cluster_user}/${monitoring_dir_name}/docker-compose/docker-compose.compute.gpu.yml -p monitoring-compute up -d
#		else
#		/usr/local/bin/docker-compose -f /home/${cfn_cluster_user}/${monitoring_dir_name}/docker-compose/docker-compose.compute.yml -p monitoring-compute up -d
		echo "End postcript" >> /home/centos/III.txt
#        	fi

	;;
esac
