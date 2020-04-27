resource "aws_s3_bucket" "codebuild-deployment-bucket" {
  bucket = "codebuild-deployment-bucket-${random_string.postfix_generator.result}"
  acl    = "private"
}

resource "aws_s3_bucket" "codebuild-source-bucket" {
  bucket = "codebuild-source-bucket-${random_string.postfix_generator.result}"
  acl    = "private"
}

resource "aws_s3_bucket_object" "project_lambda_code" {
  bucket = aws_s3_bucket.codebuild-source-bucket.bucket
  key = "deployment_package.zip"
  source = "./lambdas_code/jeager_housekeep_lambda/deployment_package.zip"

  depends_on = [module.project_lambda, aws_s3_bucket.codebuild-source-bucket]
}

resource "random_string" "postfix_generator" {
  length  = 10
  upper   = false
  lower   = true
  number  = true
  special = false
}

resource "aws_iam_role" "codebuild_project_role" {
  name               = "role_for_running_codebuild_projects"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "codebuild_allow_s3" {
  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketAcl",
      "s3:GetBucketLocation"
    ]

    resources = [
      "*"
    ]
  }
}

data "aws_iam_policy_document" "codebuild_allow_cloudwatch_policy" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "codebuild_allow_cloudwatch_policy" {
  policy = data.aws_iam_policy_document.codebuild_allow_cloudwatch_policy.json
}

resource "aws_iam_role_policy_attachment" "codebuild_allow_cloudwatch" {
  policy_arn = aws_iam_policy.codebuild_allow_cloudwatch_policy.arn
  role       = aws_iam_role.codebuild_project_role.name
}

resource "aws_iam_policy" "codebuild_allow_s3" {
  policy = data.aws_iam_policy_document.codebuild_allow_s3.json
}

resource "aws_iam_role_policy_attachment" "codebuild_allow_s3" {
  policy_arn = aws_iam_policy.codebuild_allow_s3.arn
  role       = aws_iam_role.codebuild_project_role.name
}

resource "aws_codebuild_project" "codebuild_project" {
  name         = var.codebuild_project_name
  service_role = aws_iam_role.codebuild_project_role.name
  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.codebuild-deployment-bucket.bucket
    packaging = "ZIP"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:1.0"
    type         = "LINUX_CONTAINER"
  }
  source {
    type     = "S3"
    location = "${aws_s3_bucket.codebuild-source-bucket.bucket}/deployment_package.zip"
  }

  depends_on = [aws_s3_bucket.codebuild-source-bucket]
}

resource "null_resource" "trigger_build" {
  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${aws_codebuild_project.codebuild_project.name}"
  }

  depends_on = [aws_codebuild_project.codebuild_project, aws_s3_bucket.codebuild-deployment-bucket]
}

resource "aws_cloudwatch_event_rule" "monitor_codebuild_success" {
  name        = "check_for_codebuild_success"
  description = "Watches for successfull codebuild events and triggers lamda to upload code to github release"
  role_arn    = aws_iam_role.eventbridge_triger_lambda.arn
  is_enabled  = true

  event_pattern = <<EOF
{
	"source": [
		"aws.codebuild"
	],
	"detail-type": [
		"CodeBuild Build State Change"
	],
	"detail": {
		"build-status": [
			"SUCCEEDED"
		],
        "project-name": [
            "${var.codebuild_project_name}"
        ]
	}
}
EOF
}

resource "aws_iam_role" "eventbridge_triger_lambda" {
  name               = "codebuild_event_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_event_target" "deploy_code_lambda" {
  arn  = module.lambda_codebuild_deploy.arn
  rule = aws_cloudwatch_event_rule.monitor_codebuild_success.name
  input = jsonencode(
  { "S3Bucket"     = aws_s3_bucket.codebuild-deployment-bucket.bucket,
    "FunctionName" = module.project_lambda.name,
    "S3Key"        = var.codebuild_project_name
  }
  )
}

module "lambda_codebuild_deploy" {

  source      = "./templates/lambda"
  policy      = data.aws_iam_policy_document.lambda.json
  name_prefix = "codebuild-deploy-lambda-${var.local_environment}"

  source_dir = "${path.module}/lambdas_code/deploy_lambda"
  handler    = "lambda_function.lambda_handler"
  runtime    = "python3.6"

  environment = {
    SLACK_CHANNEL     = var.slack_channel
    SLACK_USERNAME    = var.slack_username
    SLACK_EMOJI       = var.slack_emoji
    SLACK_WEBHOOK_URL = var.slack_webhook_url
  }

  tags = merge(
  var.tags,
  map("Name", var.global_name),
  map("Project", var.global_project),
  map("Environment", var.local_environment)
  )

  subnets = []
  sg = []

}

module "project_lambda" {
  source      = "./templates/lambda"
  name_prefix = var.lambda_name
  policy      = data.aws_iam_policy_document.lambda.json

  source_dir = "${path.module}/lambdas_code/jeager_housekeep_lambda"
  handler    = "lambda_function.lambda_handler"
  runtime    = "python3.6"

  tags = merge(
  var.tags,
  map("Name", var.global_name),
  map("Project", var.global_project),
  map("Environment", var.local_environment)
  )

  environment = {
    ES_HOSTNAME       = var.es_hostname
    ES_RETENTION_DAYS = var.es_retention_days
  }

  sg      = var.sg
  subnets = var.subnets

}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_codebuild_deploy.name
  principal     = "events.amazonaws.com"
}

resource "aws_lambda_permission" "allow_deploy_lambda" {
  statement_id  = "AllowExecutionLambda"
  action        = "lambda:InvokeFunction"
  function_name = module.project_lambda.name
  principal     = "lambda.amazonaws.com"
}

data "aws_iam_policy_document" "lambda" {
  statement {
    effect = "Allow"

    actions = [
      "cloudwatch:*",
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "lambda:*",
      "s3:*"
    ]

    resources = [
      "*"
    ]
  }
}