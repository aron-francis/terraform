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
    aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId, InstanceType, State.Name, Tags[?Key=='Name'].Value | [0]]" --output text | while read -r id type state name; do
        echo -e "aws_instance\t$id\t$type\t$state\t${name:-N/A}"
    done
}

# Function to get RDS instance details
get_rds_details() {
    aws rds describe-db-instances --query "DBInstances[].[DBInstanceIdentifier, DBInstanceClass]" --output text | while read -r id class; do
        echo -e "aws_db_instance\t$id\t$class\tN/A"
    done
}

# Run queries and process the output
echo "EC2 and RDS Instances:"
echo "----------------------"
(get_instance_details; get_rds_details) | column -t -s $'\t' | sort

# Count and display the number of t2.micro instances
t2_micro_count=$(aws ec2 describe-instances --filters "Name=instance-type,Values=t2.micro" --query "Reservations[].Instances[].InstanceId" --output text | wc -w)
echo ""
echo "Number of EC2 instances with t2.micro: $t2_micro_count"

# Count and display the number of t3.micro instances
t3_micro_count=$(aws ec2 describe-instances --filters "Name=instance-type,Values=t3.micro" --query "Reservations[].Instances[].InstanceId" --output text | wc -w)
echo "Number of EC2 instances with t3.micro: $t3_micro_count"