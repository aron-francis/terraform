import boto3
import json

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    
    try:
        action = event.get('action')
        instance_id = event.get('instance')
        
        if not action or not instance_id:
            raise ValueError("Both 'action' and 'instance' must be provided in the event")
        
        if action == 'start':
            response = ec2.start_instances(InstanceIds=[instance_id])
            print(f"Start response: {json.dumps(response, default=str)}")
            return {"statusCode": 200, "body": json.dumps(f"Started instance {instance_id}")}
        elif action == 'stop':
            response = ec2.stop_instances(InstanceIds=[instance_id])
            print(f"Stop response: {json.dumps(response, default=str)}")
            return {"statusCode": 200, "body": json.dumps(f"Stopped instance {instance_id}")}
        else:
            raise ValueError(f"Invalid action: {action}")
    
    except Exception as e:
        print(f"Error: {str(e)}")
        print(f"Event: {json.dumps(event)}")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": str(e)})
        }