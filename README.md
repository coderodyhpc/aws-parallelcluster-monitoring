# Grafana Dashboard for WRF cluster 

This is a sample solution based on Grafana for monitoring various component of an HPC cluster running WRF and based on odyhpc AMIs (from AWS Marketplace).

The HPC cluster has to be launched with AWS ParallelCluster. More information about AWS ParallelCluster is available on: https://aws.amazon.com/hpc/parallelcluster/, https://github.com/aws/aws-parallelcluster (source Code on Git-Hub), and official documentation at https://docs.aws.amazon.com/parallelcluster/.

This solution is adapted from https://github.com/aws-samples/aws-parallelcluster-monitoring by odyhpc and works with several open-source projects and tools including Grafana, Prometheus,Prometheus Pushgateway, Nginx, Prometheus-Slurm-Exporter & Node_exporter.
Note: *while almost all components are under the Apache2 license, only **[Prometheus-Slurm-Exporter is licensed under GPLv3](https://github.com/vpenso/prometheus-slurm-exporter/blob/master/LICENSE)**, you need to be aware of it and accept the license terms before proceeding and installing this component.*


## License

This library is licensed under the MIT-0 License. See the [LICENSE](https://github.com/aws-samples/aws-parallelcluster-monitoring/blob/main/LICENSE) file.
