variable "github_repository" {
  type = string
}

variable "lambda_name" {
  type = string
}

variable "codebuild_project_name" {
  type = string
}

variable "global_name" {
  description = "Global name of this project/account with environment"
  type        = string
  default     = ""
}

variable "global_project" {
  description = "Global name of this project (without environment)"
  type        = string
  default     = ""
}

variable "local_environment" {
  description = "Local name of this environment (eg, prod, stage, dev, feature1)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags (key-value pairs) passed to resources."
  type        = map(string)
  default     = {}
}

variable "slack_channel" {
  description = "Slack channel to send scan notification to."
  type        = string
}

variable "slack_username" {
  description = "Slack username to be displayed with the message."
  type        = string
  default     = "ecr-scan"
}

variable "slack_emoji" {
  description = "Slack icon to be displayed with the message."
  type        = string
  default     = ":aws:"
}

variable "slack_webhook_url" {
  description = "Slack webhook to send the message to."
  type        = string
}

variable "es_hostname" {
  type = string
}

variable "es_retention_days" {
  type = number
}

variable "vpc" {
  type        = string
  description = "VPC where the components will be deployed"
}

variable "subnets" {
  description = "A list of subnet ids where the components will be available. E.g. '[\"subnet-123\", \"subnet-456\"]'"
}

variable "sg" {
}