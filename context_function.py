import json
import boto3
from datetime import datetime
import os
  

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DDB_TABLE'])

def lambda_handler(event, context):
    print('event:', json.dumps(event))
    
    # Store statistics in DynamoDB
    timestamp = str(datetime.utcnow())
    table.put_item(
        Item={
            'user': "user",
            'geolocation': "some location",
            'timestamp': timestamp
        }
    )    
    
    # Invoke other lambda
    client = boto3.client('lambda')
    response = client.invoke(
        FunctionName = 'arn:aws:lambda:eu-west-3:084525207573:function:lambda2',
        InvocationType = 'RequestResponse',
        Payload = json.dumps(event)
    )

    return {
        "statusCode": 200,
        "body": json.loads(json.dumps(response, default=str))
    }
