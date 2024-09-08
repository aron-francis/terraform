import boto3
import json
import logging
import time

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def wait_for_instance_state(ec2, instance_id, target_state, max_attempts=30):
    for _ in range(max_attempts):
        instance_info = ec2.describe_instances(InstanceIds=[instance_id])['Reservations'][0]['Instances'][0]
        current_state = instance_info['State']['Name']
        if current_state == target_state:
            return True
        time.sleep(10)  # Wait for 10 seconds before checking again
    return False

def find_active_instance(ec2):
    instances = ec2.describe_instances(Filters=[{'Name': 'instance-state-name', 'Values': ['running', 'stopped']}])
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            return instance['InstanceId']
    return None

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        ec2 = boto3.client('ec2')
        
        # Check if the event is from SNS
        if 'Records' in event and len(event['Records']) > 0 and 'Sns' in event['Records'][0]:
            message = json.loads(event['Records'][0]['Sns']['Message'])
            logger.info(f"Parsed SNS message: {json.dumps(message)}")
            instance_id = message['Trigger']['Dimensions'][0]['value']
        else:
            # For direct invocation or testing, find an active instance
            instance_id = find_active_instance(ec2)
            if not instance_id:
                logger.error("No active instances found in the account")
                raise ValueError("No active instances found in the account")
            logger.info(f"Found active instance: {instance_id}")
        
        logger.info(f"Processing instance ID: {instance_id}")
        
        instance_info = ec2.describe_instances(InstanceIds=[instance_id])['Reservations'][0]['Instances'][0]
        current_state = instance_info['State']['Name']
        current_type = instance_info['InstanceType']
        logger.info(f"Current instance state: {current_state}")
        logger.info(f"Current instance type: {current_type}")
        
        if current_type == 't2.micro':
            logger.info(f"Instance {instance_id} is already t2.micro. No action needed.")
            return {
                'statusCode': 200,
                'body': json.dumps(f'Instance {instance_id} is already t2.micro. No action taken.'),
                'instance_id': instance_id
            }
        
        if current_type == 't3.micro':
            target_type = 't2.micro'
        else:
            logger.info(f"Instance {instance_id} is not t3.micro. No action needed.")
            return {
                'statusCode': 200,
                'body': json.dumps(f'Instance {instance_id} is {current_type}. No action taken.'),
                'instance_id': instance_id
            }
        
        if current_state == 'running':
            logger.info(f"Stopping instance {instance_id}")
            ec2.stop_instances(InstanceIds=[instance_id])
            logger.info(f"Waiting for instance to stop")
            if not wait_for_instance_state(ec2, instance_id, 'stopped'):
                raise TimeoutError("Instance did not stop in time")
            current_state = 'stopped'
        
        if current_state == 'stopped':
            logger.info(f"Modifying instance type to {target_type}")
            ec2.modify_instance_attribute(InstanceId=instance_id, Attribute='instanceType', Value=target_type)
            logger.info(f"Starting instance {instance_id}")
            ec2.start_instances(InstanceIds=[instance_id])
            logger.info(f"Waiting for instance to start")
            if not wait_for_instance_state(ec2, instance_id, 'running'):
                raise TimeoutError("Instance did not start in time")
            logger.info(f"Instance resized and started successfully")
        else:
            logger.info(f"Instance {instance_id} is in {current_state} state. No action taken.")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Instance {instance_id} processed. Current state: {current_state}, Type: {current_type}'),
            'instance_id': instance_id
        }
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        raise
