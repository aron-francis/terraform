#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 [-h]"
    echo "  -h  Display this help message"
    exit 1
}

# Parse command line options
while getopts ":h" opt; do
    case ${opt} in
        h )
            usage
            ;;
        \? )
            echo "Invalid Option: -$OPTARG" 1>&2
            usage
            ;;
    esac
done

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null
then
    echo "AWS CLI could not be found. Please install AWS CLI to use this script."
    exit 1
fi  # Changed from } to fi

# Function to get instance details
get_instance_details() {
    aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId, InstanceType, State.Name, Tags[?Key=='Name'].Value | [0], LaunchTime, StateTransitionReason]" --output text | while read -r id type state name launch_time state_reason; do
        end_time=$(echo "$state_reason" | sed -n 's/.*(\(.*\)).*/\1/p' || echo "N/A")
        formatted_launch_time=$(date -j -f "%Y-%m-%dT%H:%M:%S.000Z" "$launch_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$launch_time")
        echo -e "EC2\t$id\t$type\t$state\t${name:-N/A}\t$formatted_launch_time\t$end_time"
    done
}

# Function to get RDS instance details
get_rds_details() {
    aws rds describe-db-instances --query "DBInstances[].[DBInstanceIdentifier, DBInstanceClass, DBInstanceStatus, InstanceCreateTime, DBName]" --output text | while read -r id class status create_time db_name; do
        formatted_create_time=$(date -j -f "%Y-%m-%dT%H:%M:%S.000Z" "$create_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$create_time")
        echo -e "RDS\t$id\t$class\t$status\t${db_name:-N/A}\t$formatted_create_time\tN/A"
    done
}

# Run queries and process the output
echo "EC2 and RDS Instances:"
echo "----------------------"
echo -e "Type\tID\t\t\t\tInstance Type\tState\t\tName\t\tStart Time\tEnd Time"
echo -e "========================================================================================================================"

(get_instance_details; get_rds_details) | column -t -s $'\t'

# Count and display the number of t2.micro instances
t2_micro_count=$(aws ec2 describe-instances --filters "Name=instance-type,Values=t2.micro" --query "Reservations[].Instances[].InstanceId" --output text | wc -w)
echo ""
echo "Number of EC2 instances with t2.micro: $t2_micro_count"

# Count and display the number of t3.micro instances
t3_micro_count=$(aws ec2 describe-instances --filters "Name=instance-type,Values=t3.micro" --query "Reservations[].Instances[].InstanceId" --output text | wc -w)
echo "Number of EC2 instances with t3.micro: $t3_micro_count"