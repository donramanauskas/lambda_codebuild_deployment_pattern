import boto3, json, logging

from botocore.exceptions import ClientError

logger = logging.getLogger()


def deploy_lambda(FunctionName, S3Bucket, S3Key):
    client = boto3.client("lambda")
    try:
        response = client.update_function_code(
            FunctionName=FunctionName,
            Publish=True,
            S3Bucket=S3Bucket,
            S3Key=S3Key
        )
        return response
    except ClientError as c:
        logger.error("Failed to upload lambda code from S3 with, client error: {}".format(c))
        return



def lambda_handler(event, context):

    FunctionName=event["FunctionName"]
    S3Bucket=event["S3Bucket"]
    S3Key=event["S3Key"]

    deploy_lambda(FunctionName, S3Bucket, S3Key)