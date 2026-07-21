from pydantic import BaseModel


class LambdaEvent(BaseModel):
    name: str = "World"
