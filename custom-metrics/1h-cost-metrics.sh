#!/bin/bash
#

#source the AWS ParallelCluster profile
. /etc/parallelcluster/cfnconfig

export AWS_DEFAULT_REGION=$cfn_region
aws_region_long_name=$(python3 /usr/local/bin/aws-region.py $cfn_region)

masterInstanceType=$(ec2-metadata -t | awk '{print $2}')
masterInstanceId=$(ec2-metadata -i | awk '{print $2}')


####################### Master #########################
master_node_h_price=$(aws pricing get-products \
  --region us-east-1 \
  --service-code AmazonEC2 \
  --filters 'Type=TERM_MATCH,Field=instanceType,Value='$masterInstanceType \
            'Type=TERM_MATCH,Field=location,Value='"${aws_region_long_name}" \
            'Type=TERM_MATCH,Field=preInstalledSw,Value=NA' \
            'Type=TERM_MATCH,Field=operatingSystem,Value=Linux' \
            'Type=TERM_MATCH,Field=tenancy,Value=Shared' \
            'Type=TERM_MATCH,Field=capacitystatus,Value=UnusedCapacityReservation' \
  --output text \
  --query 'PriceList' \
  | jq -r '.terms.OnDemand | to_entries[] | .value.priceDimensions | to_entries[] | .value.pricePerUnit.USD')
  
echo "master_node_cost $master_node_h_price" | curl --data-binary @- http://127.0.0.1:9091/metrics/job/cost
  
echo "master_node_cost $master_node_h_price" >> /home/centos/info.txt 

####################### FSX #########################
fsx_size_gb=$(aws cloudformation describe-stacks --stack-name $stack_name --region $cfn_region \
              | jq -r '.Stacks[0].Parameters | map(select(.ParameterKey == "FSXOptions"))[0].ParameterValue' \
              | awk -F "," '{print $3}')
              
fsx_type=$(aws cloudformation describe-stacks --stack-name $stack_name --region $cfn_region \
              | jq -r '.Stacks[0].Parameters | map(select(.ParameterKey == "FSXOptions"))[0].ParameterValue' \
              | awk -F "," '{print $9}')
            
fsx_throughput=$(aws cloudformation describe-stacks --stack-name $stack_name --region $cfn_region \
              | jq -r '.Stacks[0].Parameters | map(select(.ParameterKey == "FSXOptions"))[0].ParameterValue' \
              | awk -F "," '{print $10}')

if [[ $fsx_type = "SCRATCH_2" ]] || [[ $fsx_type = "SCRATCH_1" ]]; then
  fsx_cost_gb_month=$(aws pricing get-products \
                      --region us-east-1 \
                      --service-code AmazonFSx \
                      --filters 'Type=TERM_MATCH,Field=location,Value='"${aws_region_long_name}" \
                      'Type=TERM_MATCH,Field=fileSystemType,Value=Lustre' \
                      'Type=TERM_MATCH,Field=throughputCapacity,Value=N/A' \
                      --output text \
                      --query 'PriceList' \
                      | jq -r '.terms.OnDemand | to_entries[] | .value.priceDimensions | to_entries[] | .value.pricePerUnit.USD')

elif [ $fsx_type = "PERSISTENT_1" ]; then
  fsx_cost_gb_month=$(aws pricing get-products \
                      --region us-east-1 \
                      --service-code AmazonFSx \
                      --filters 'Type=TERM_MATCH,Field=location,Value='"${aws_region_long_name}" \
                      'Type=TERM_MATCH,Field=fileSystemType,Value=Lustre' \
                      'Type=TERM_MATCH,Field=throughputCapacity,Value='$fsx_throughput \
                      --output text \
                      --query 'PriceList' \
                      | jq -r '.terms.OnDemand | to_entries[] | .value.priceDimensions | to_entries[] | .value.pricePerUnit.USD')

else
  fsx_cost_gb_month=0
fi

fsx=$(echo "scale=2; $fsx_cost_gb_month * $fsx_size_gb / 720" | bc)
echo "fsx_cost $fsx" | curl --data-binary @- http://127.0.0.1:9091/metrics/job/cost


#parametrize:
ebs_volume_total_cost=0
ebs_volume_ids=$(aws ec2 describe-instances     --instance-ids $masterInstanceId \
              | jq -r '.Reservations | to_entries[].value | .Instances | to_entries[].value | .BlockDeviceMappings | to_entries[].value | .Ebs.VolumeId')

for ebs_volume_id in $ebs_volume_ids
do
  ebs_volume_type=$(aws ec2 describe-volumes --volume-ids $ebs_volume_id | jq -r '.Volumes | to_entries[].value.VolumeType')
  #ebs_volume_iops=$(aws ec2 describe-volumes --volume-ids $ebs_volume_id | jq -r '.Volumes | to_entries[].value.Iops')
  ebs_volume_size=$(aws ec2 describe-volumes --volume-ids $ebs_volume_id | jq -r '.Volumes | to_entries[].value.Size')
  
  ebs_cost_gb_month=$(aws --region us-east-1 pricing get-products \
    --service-code AmazonEC2 \
    --query 'PriceList' \
    --output text \
    --filters 'Type=TERM_MATCH,Field=location,Value='"${aws_region_long_name}" \
            'Type=TERM_MATCH,Field=productFamily,Value=Storage' \
            'Type=TERM_MATCH,Field=volumeApiName,Value='$ebs_volume_type \
    | jq -r '.terms.OnDemand | to_entries[] | .value.priceDimensions | to_entries[] | .value.pricePerUnit.USD')

  ebs_volume_cost=$(echo "scale=2; $ebs_cost_gb_month * $ebs_volume_size / 720" | bc)
  ebs_volume_total_cost=$(echo "scale=2; $ebs_volume_total_cost + $ebs_volume_cost" | bc)
done

echo "ebs_master_cost $ebs_volume_total_cost" | curl --data-binary @- http://127.0.0.1:9091/metrics/job/cost
