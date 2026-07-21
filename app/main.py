import logging

from app.environment import LambdaEnvironment
from app.models.event import LambdaEvent

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

environment: LambdaEnvironment = LambdaEnvironment()

def handler(event, context):
    lambda_event = LambdaEvent.model_validate(event)
    logger.info(f"{environment.greeting}, {lambda_event.name}!")
