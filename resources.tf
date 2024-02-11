# Dynamo DB table
resource "aws_dynamodb_table" "weather_stats" {
  name           = "weather_stats"
  billing_mode   = "PROVISIONED"
  read_capacity  = 2
  write_capacity = 2  
  hash_key       = "user" 
  range_key      = "timestamp"
  attribute {
    name = "user"
    type = "S"
    }
  attribute {
    name = "timestamp"
    type = "S"
    }
  
  global_secondary_index {
    name               = "weather_index"
    hash_key           = "user"
    range_key          = "timestamp"
    write_capacity     = 2
    read_capacity      = 2
    projection_type    = "INCLUDE"
    non_key_attributes = ["geolocation"]
  }
}

resource "null_resource" "always_run" {
  triggers = {
    timestamp = "${timestamp()}"
  }
}

# Lambda Function
resource "aws_lambda_function" "context_function" {
  function_name = "lambda1"
  runtime       = "python3.12"
  handler       = "context_function.lambda_handler"
  filename      = "lambda1.zip"
  role          = aws_iam_role.lambda_execution_role.arn
  
  environment {
    variables = {
      DDB_TABLE = "weather_stats",
    }
  }

  lifecycle {
   replace_triggered_by = [
      null_resource.always_run
    ]
  }
  
}

# Lambda Function
resource "aws_lambda_function" "forecast_function" {
  function_name = "lambda2"
  runtime       = "python3.12"
  handler       = "forecast_function.lambda_handler"
  filename      = "lambda2.zip"
  role          = aws_iam_role.lambda_execution_role.arn
}

resource "aws_lambda_function_url" "forecast_url" {
  function_name      = aws_lambda_function.forecast_function.function_name
  authorization_type = "NONE"
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com",
        },
      },  
    ],
  })
}

data "aws_iam_policy_document" "lambda_policy_document_ddb" {
  statement {
    actions = [
      "dynamodb:PutItem",
    ]
    resources = [
		aws_dynamodb_table.weather_stats.arn
    ]
  }
}

data "aws_iam_policy_document" "lambda_policy_document_lambda" {
  statement {
    actions = [
      "lambda:InvokeFunction",
	  "lambda:InvokeAsync",
    ]
    resources = [
		aws_lambda_function.forecast_function.arn
    ]
  }
}

resource "aws_iam_policy" "dynamodb_lambda_policy" {
  name        = "dynamodb-lambda-policy"
  description = "This policy will be used by the lambda to write get data from DynamoDB"
  policy      = data.aws_iam_policy_document.lambda_policy_document_ddb.json
}

resource "aws_iam_role_policy_attachment" "lambda_attachements_ddb" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.dynamodb_lambda_policy.arn
}

resource "aws_iam_policy" "lambda_invoke_policy" {
  name        = "lambda-invoke-policy"
  description = "This policy will be used by the lambda to write get data from DynamoDB"
  policy      = data.aws_iam_policy_document.lambda_policy_document_lambda.json
}

resource "aws_iam_role_policy_attachment" "lambda_attachements_lambda" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_invoke_policy.arn
}

resource "aws_api_gateway_rest_api" "demo_rest_api" {
  name        = "demo_rest_api"
  description = "This is my API for demonstration purposes"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }  
}

resource "aws_api_gateway_resource" "invoke" {
  parent_id   = aws_api_gateway_rest_api.demo_rest_api.root_resource_id
  path_part   = "invoke"
  rest_api_id = aws_api_gateway_rest_api.demo_rest_api.id
}

resource "aws_api_gateway_method" "method" {
  authorization = "NONE"
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.invoke.id
  rest_api_id   = aws_api_gateway_rest_api.demo_rest_api.id
}

#import {
#  to = aws_api_gateway_integration.integration_GET #aws_api_gateway_method.method
#  id = "0ppoy48qze/dfmxm7/GET"
#}

resource "aws_api_gateway_integration" "integration_GET" {
  http_method = aws_api_gateway_method.method.http_method
  resource_id = aws_api_gateway_resource.invoke.id
  rest_api_id = aws_api_gateway_rest_api.demo_rest_api.id
  integration_http_method = "POST"
  type                    = "AWS"
  connection_type         = "INTERNET"
  content_handling        = "CONVERT_TO_TEXT"  
  uri                     = aws_lambda_function.context_function.invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.context_function.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  #source_arn = "arn:aws:execute-api:eu-west-3:084525207573:${aws_api_gateway_rest_api.demo_rest_api.id}/*/${aws_api_gateway_method.POST.http_method}${aws_api_gateway_resource.invoke.path}"
  source_arn = "arn:aws:execute-api:eu-west-3:084525207573:${aws_api_gateway_rest_api.demo_rest_api.id}/*/*/*"

}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.demo_rest_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.invoke.id,
	  aws_api_gateway_method.method.id,
      aws_api_gateway_integration.integration_GET.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "example" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.demo_rest_api.id
  stage_name    = "example"
}

# Output API Gateway URL
output "api_gateway_url" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}${aws_api_gateway_stage.example.stage_name}${aws_api_gateway_resource.invoke.path}"
}



