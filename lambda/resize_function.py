import boto3
import json
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        ec2 = boto3.client('ec2')
        
        # Check if the event is from SNS
        if 'Records' in event and len(event['Records']) > 0 and 'Sns' in event['Records'][0]:
            # Parse the SNS message
            message = json.loads(event['Records'][0]['Sns']['Message'])
            logger.info(f"Parsed SNS message: {json.dumps(message)}")
            
            # Extract instance ID from the message
            instance_id = message['Trigger']['Dimensions'][0]['value']
        else:
            # For direct invocation or testing
            instance_id = event.get('instance_id', 'i-08dc9b3a3358fb704')  # Default to your instance ID
        
        logger.info(f"Processing instance ID: {instance_id}")
        
        # Get current instance state and type
        instance_info = ec2.describe_instances(InstanceIds=[instance_id])['Reservations'][0]['Instances'][0]
        current_state = instance_info['State']['Name']
        current_type = instance_info['InstanceType']
        logger.info(f"Current instance state: {current_state}")
        logger.info(f"Current instance type: {current_type}")
        
        if current_type == 't3.micro':
            target_type = 't2.micro'
        else:
            target_type = 't3.micro'
        
        if current_state == 'running':
            logger.info(f"Stopping instance {instance_id}")
            ec2.stop_instances(InstanceIds=[instance_id])
            logger.info(f"Stop initiated for instance {instance_id}")
        elif current_state == 'stopped':
            logger.info(f"Modifying instance type to {target_type}")
            ec2.modify_instance_attribute(InstanceId=instance_id, Attribute='instanceType', Value=target_type)
            logger.info(f"Starting instance {instance_id}")
            ec2.start_instances(InstanceIds=[instance_id])
            logger.info(f"Start initiated for instance {instance_id}")
        else:
            logger.info(f"Instance {instance_id} is in {current_state} state. No action taken.")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Instance resize operation initiated')
        }
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        raise
