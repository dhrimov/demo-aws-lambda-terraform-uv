module "lambda" {
  source  = "moritzzimmer/lambda/aws"
  version = "8.6.0"

  filename         = "lambda.zip"
  function_name    = "demo-lambda"
  handler          = "app.main.handler"
  runtime          = "python3.13"
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")

  architectures = ["arm64"]

  environment = {
    variables = {
      GREETING = "Hi"
    }
  }
}