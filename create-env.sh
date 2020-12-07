#!/bin/bash

set -ex

# TODO: create elastic ip.

# Available configuration :
AWS_REGION="us-west-1"
# NAT_GW_IP_ALLOC_ID="eipalloc-a64b7f99"
INSTANCE_AMI="ami-0e49017a141c7e80c"
VM_INSTANCE_AMI="ami-0e49017a141c7e80c"
SWITCH_INSTANCE_AMI="ami-0e49017a141c7e80c"
KEYPAIR_NAME="us-west-2"
NAME_PREFIX="l3-nw-training"

SCRIPTDIR=$(dirname ${BASH_SOURCE[0]})
if [ -f $SCRIPTDIR/provision_aws-conf.sh ]; then
  source $SCRIPTDIR/provision_aws-conf.sh
fi

LOGDIR='./aws-log/'
mkdir -p $LOGDIR

check_params ()
{
  if [[ "$AWS_REGION" = "" ]] || \
    [[ "$INSTANCE_AMI" = "" ]] || \
    [[ "$VM_INSTANCE_AMI" = "" ]] || \
    [[ "$SWITCH_INSTANCE_AMI" = "" ]] || \
    [[ "$KEYPAIR_NAME" = "" ]]; then
    echo "Please fill in required params"
    exit 1
  fi
}

create_vpc ()
{
  echo "Creating VPC"
  aws ec2 create-vpc \
    --cidr-block 192.168.0.0/16 > $LOGDIR/create-vpc.log
  VPCID=$(cat $LOGDIR/create-vpc.log | jq -r .Vpc.VpcId)

  echo "Creating subnets"

  aws ec2 create-subnet \
    --availability-zone ${AWS_REGION}a \
    --vpc-id $VPCID \
    --cidr-block 192.168.128.0/19 > $LOGDIR/create-subnet-public.log
  PUBLIC_SUBNET_ID=$(cat $LOGDIR/create-subnet-public.log | jq -r .Subnet.SubnetId)

  aws ec2 create-subnet \
    --availability-zone ${AWS_REGION}a \
    --vpc-id $VPCID \
    --cidr-block 192.168.0.0/19 > $LOGDIR/create-subnet-private.log
  PRIVATE_SUBNET_ID=$(cat $LOGDIR/create-subnet-private.log | jq -r .Subnet.SubnetId)

  aws ec2 create-subnet \
    --availability-zone ${AWS_REGION}b \
    --vpc-id $VPCID \
    --cidr-block 192.168.32.0/19 > $LOGDIR/create-subnet-private2.log
  PRIVATE_SUBNET_ID2=$(cat $LOGDIR/create-subnet-private2.log | jq -r .Subnet.SubnetId)

  echo "Creating IGW"
  aws ec2 create-internet-gateway > $LOGDIR/create-internet-gateway.log
  INTERNET_GW_ID=$(cat $LOGDIR/create-internet-gateway.log | jq -r .InternetGateway.InternetGatewayId)
  aws ec2 attach-internet-gateway \
    --internet-gateway-id $INTERNET_GW_ID \
    --vpc-id $VPCID > $LOGDIR/attach-internet-gateway.log

      aws ec2 create-route-table \
        --vpc-id $VPCID > $LOGDIR/create-route-table-private.log
      PRIVATE_RT_ID=$(cat $LOGDIR/create-route-table-private.log | jq -r .RouteTable.RouteTableId)

      aws ec2 associate-route-table \
        --subnet-id $PRIVATE_SUBNET_ID \
        --route-table-id $PRIVATE_RT_ID > $LOGDIR/associate-route-table-private.log

      aws ec2 associate-route-table \
        --subnet-id $PRIVATE_SUBNET_ID2 \
        --route-table-id $PRIVATE_RT_ID > $LOGDIR/associate-route-table-private2.log

      aws ec2 create-route-table \
        --vpc-id $VPCID > $LOGDIR/create-route-table-public.log
      PUBLIC_RT_ID=$(cat $LOGDIR/create-route-table-public.log | jq -r .RouteTable.RouteTableId)

      aws ec2 associate-route-table \
        --subnet-id $PUBLIC_SUBNET_ID \
        --route-table-id $PUBLIC_RT_ID > $LOGDIR/associate-route-table-public.log

      aws ec2 create-route \
        --route-table-id $PUBLIC_RT_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $INTERNET_GW_ID > $LOGDIR/create-route-igw.log
        
    echo "Configuring NAT gateway"
    aws ec2 allocate-address > $LOGDIR/allocate-elastic-ip.log

    NAT_GW_IP_ALLOC_ID=$(cat $LOGDIR/allocate-elastic-ip.log | jq -r .AllocationId)

    aws ec2 create-nat-gateway \
    --allocation-id $NAT_GW_IP_ALLOC_ID \
    --subnet-id $PUBLIC_SUBNET_ID > $LOGDIR/create-nat-gateway.log
    NAT_GW_ID=$(cat $LOGDIR/create-nat-gateway.log | jq -r .NatGateway.NatGatewayId)

    sleep 120 #nat gateway takes 100 seconds for creation
    #   TODO: add condition to check if nateway in Available status.

    aws ec2 create-route \
      --route-table-id $PRIVATE_RT_ID \
      --destination-cidr-block 0.0.0.0/0 \
      --nat-gateway-id $NAT_GW_ID > $LOGDIR/create-route-nat-gw.log

  # aws ec2 create-security-group \
  #   --description "Only ssh" \
  #   --vpc-id $VPCID \
  #   --group-name "${NAME_PREFIX}-ssh-sg" > $LOGDIR/create-security-group-public.log
  # PUBLIC_SG_ID=$(cat $LOGDIR/create-security-group-public.log | jq -r .GroupId)

  aws ec2 create-security-group \
    --description "Internal" \
    --vpc-id $VPCID \
    --group-name "${NAME_PREFIX}-internal-sg" > $LOGDIR/create-security-group-private.log
  PRIVATE_SG_ID=$(cat $LOGDIR/create-security-group-private.log | jq -r .GroupId)

  # aws ec2 authorize-security-group-ingress \
  #   --group-id $PUBLIC_SG_ID \
  #   --protocol tcp \
  #   --port 22 \
  #   --cidr 0.0.0.0/0 > $LOGDIR/authorize-security-group-ingress-public.log

  aws ec2 authorize-security-group-ingress \
    --group-id $PRIVATE_SG_ID \
    --protocol tcp \
    --port 22 \
    --source-group $PRIVATE_SG_ID > $LOGDIR/authorize-security-group-ingress-private-ssh.log

  aws ec2 authorize-security-group-ingress \
    --group-id $PRIVATE_SG_ID \
    --protocol all \
    --source-group $PRIVATE_SG_ID > $LOGDIR/authorize-security-group-ingress-private.log
    echo "done creating vpc"


  aws ec2 modify-vpc-attribute --vpc-id ${VPCID} --enable-dns-support "{\"Value\":true}"
  aws ec2 modify-vpc-attribute --vpc-id ${VPCID} --enable-dns-hostnames "{\"Value\":true}"

#   creating vpc endpoint. It takes 75 seconds for each endpoint creation.
  aws ec2 create-vpc-endpoint --vpc-endpoint-type Interface --vpc-id $VPCID --service-name com.amazonaws.us-west-1.logs --security-group-ids $PRIVATE_SG_ID
  aws ec2 create-vpc-endpoint --vpc-endpoint-type Interface --vpc-id $VPCID --service-name com.amazonaws.us-west-1.monitoring --security-group-ids $PRIVATE_SG_ID
  aws ec2 create-vpc-endpoint --vpc-endpoint-type Interface --vpc-id $VPCID --service-name com.amazonaws.us-west-1.synthetics --security-group-ids $PRIVATE_SG_ID
  sleep 80
  echo "initiated vpc ep creation"
  echo $(date)

  echo "Create IAM role"
  aws iam create-role --role-name troubleshooting-iam-role --assume-role-policy-document file://trust.json > $LOGDIR/create-iam-role.log
  IAM_ROLE_ARN=$(cat $LOGDIR/create-iam-role.log | jq -r .Role.Arn)
  aws iam attach-role-policy \
  --role-name troubleshooting-iam-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

  aws iam attach-role-policy \
  --role-name troubleshooting-iam-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

  sleep 10
}

create_alb_and_target_group()
{
  #Create a application loadbalencer
  LOADBALENCERNAME="troubleshooting-alb"
  alb_name=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName==\`${LOADBALENCERNAME}\`].LoadBalancerName" --output text)
  if [ -z $alb_name ]
  then
  aws elbv2 create-load-balancer --name $LOADBALENCERNAME --subnets $PRIVATE_SUBNET_ID $PRIVATE_SUBNET_ID2 --security-groups $SECURITYGROUP
  else
  echo "Info: Load balencer name is already present, please change if new load balencer required."
  fi

  #Create a target group for loadbalencer
  TARGETNAME="troubleshooting-alb-target"
  target_name=$(aws elbv2 describe-target-groups --query "TargetGroups[?TargetGroupName==\`${TARGETNAME}\`].TargetGroupName" --output text)
  if [ -z $target_name ]
  then
    aws elbv2 create-target-group --name $TARGETNAME --target-type lambda > $LOGDIR/create-alb-target-group.log
  else
    echo "Info: Target group name is already present, please change if new function required."
  fi

  #Create a lambda function
  FUNCTIONNAME="troubleshooting-lambda"
  lambda_function_name=$(aws lambda list-functions --query "Functions[?FunctionName==\`${FUNCTIONNAME}\`].FunctionName" --output text || true)
  if [ -z $lambda_function_name ]
  then
    zip helloworld_27.py.zip helloworld_27.py
    aws lambda create-function --function-name $FUNCTIONNAME --zip-file fileb://helloworld_27.py.zip --handler 'helloworld_27.lambda_handler' --runtime 'python2.7' --role $IAM_ROLE_ARN
  else
    echo "Info: Lambda function name is already present, please change if new function required."
  fi

  aws lambda add-permission --function-name $FUNCTIONNAME --statement-id load-balancer --action "lambda:InvokeFunction" --principal elasticloadbalancing.amazonaws.com
  targetARN=$(aws elbv2 describe-target-groups --query "TargetGroups[?TargetGroupName==\`${TARGETNAME}\`].TargetGroupArn" --output text)
  targetlambda=$(aws lambda list-functions --query "Functions[?FunctionName==\`${FUNCTIONNAME}\`].FunctionArn" --output text)

  #To register a Lambda function as a target
  aws elbv2 register-targets --target-group-arn $targetARN --targets Id=$targetlambda
  LoadbalencerArn=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName==\`${LOADBALENCERNAME}\`].LoadBalancerArn" --output text)

  #To create a listener for load balancer with a default rule that forwards requests to target group
  aws elbv2 create-listener --load-balancer-arn $LoadbalencerArn --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$targetARN

  #Wait for ALB to be active
  state=""
  while [[ $state != "active" ]];
  do
  state=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName==\`${LOADBALENCERNAME}\`].State" --output text)
  sleep 10
  done
}

delete_resources()
{

  
  aws lambda delete-function --function-name troubleshooting-lambda

  LOADBALENCERNAME="troubleshooting-alb"
  alb_arn=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName==\`${LOADBALENCERNAME}\`].LoadBalancerArn" --output text)
  aws elbv2 delete-load-balancer --load-balancer-arn ${alb_arn}

  TARGETNAME="troubleshooting-alb-target"
  targetARN=$(aws elbv2 describe-target-groups --query "TargetGroups[?TargetGroupName==\`${TARGETNAME}\`].TargetGroupArn" --output text)

  sleep 10
  aws elbv2 delete-target-group --target-group-arn ${targetARN}

  aws iam detach-role-policy --role-name troubleshooting-iam-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  aws iam detach-role-policy --role-name troubleshooting-iam-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
  aws iam delete-role --role-name troubleshooting-iam-role

  NAT_GW_ID=$(cat $LOGDIR/create-nat-gateway.log | jq -r .NatGateway.NatGatewayId)
  aws ec2 delete-nat-gateway --nat-gateway-id ${NAT_GW_ID}
  sleep 120 #for nat gateway deletion

  NAT_GW_IP_ALLOC_ID=$(cat $LOGDIR/allocate-elastic-ip.log | jq -r .AllocationId)
  aws ec2 release-address --allocation-id ${NAT_GW_IP_ALLOC_ID}
}
 
if [[ "$1" = "create" ]]; then
  check_params
  create_vpc
  create_alb_and_target_group
#   create_bastion
elif [[ "$1" = "delete" ]]; then
  delete_resources
else
  echo "Usage:"
  echo "./create-env.sh create"
  echo "./create-env.sh delete"
fi





