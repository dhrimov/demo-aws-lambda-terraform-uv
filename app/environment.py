from pydantic_settings import BaseSettings


class LambdaEnvironment(BaseSettings):
    greeting: str = "Hello"
