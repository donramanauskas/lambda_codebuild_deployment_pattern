import os
import logging
import elasticsearch
import curator
import json

logger = logging.getLogger()

client = elasticsearch.Elasticsearch(
    [
        {
            "host": os.environ['ES_HOSTNAME'],
            'port': 443
        }
    ],
    use_ssl=True
)


def lambda_handler(event, context):

    try:
        retention_days = int(os.environ['ES_RETENTION_DAYS'])
    except ValueError:
        logger.error("ES_RETENTION_DAYS must be set as environment variable")
        return
    try:
        index_list = curator.IndexList(client)
    except Exception as e:
        logger.error("Failed to connect to ES DB with error: {}".format(e))
        return

    try:
        index_list.filter_by_regex(
            kind='prefix',
            value='jaeger-'
        )
    except Exception as e:
        logger.error("Filtering by jeager preffix failed, received error: {}".format(e))
        return

    try:
        index_list.filter_by_age(
            source='creation_date',
            direction='older',
            unit='days',
            unit_count=retention_days
        )
    except Exception as e:
        logger.error("Filtering by age failed with error: {}".format(e))
        return

    indexes_to_delete = index_list.working_list()

    if len(indexes_to_delete) > 0:
        try:
            logger.info("Deleting indexes: {}".format(indexes_to_delete.sort()))
            curator.DeleteIndices(index_list).do_action()
        except Exception as e:
            logger.error("Got error {} when trying to delete indexes".format(e))
            return

    return {
        'statusCode': 200,
        'body': json.dumps('Removed indexes for last {} days'.format(retention_days))
    }