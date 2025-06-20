variable "github_codestarconnections_connection_arn" {
  type        = string
  description = "ARN of the Github.com configuration that has read access to the git repo named in github_repo"
}

variable "namespace" {
  type        = string
  description = "prefix used for naming resources created by this module"
}

variable "terraform_state_bucket" {
  type        = string
  description = "name of the S3 bucket were Terraform remote state for the target resources can be found"
}

variable "terraform_state_key" {
  type        = string
  description = "key/prefix of the S3 object holding Terraform remote state for the target resources"
}

variable "github_repo" {
  type        = string
  description = "reference to the Github repo holding the target Terraform resource configuration; r.g., my-org/my-repo"
}

variable "git_branch" {
  type    = string
  description = "git branch or tag in the repo holding the target Terraform resource configuration"
  default = "main"
}

variable "global_tags" {
  type        = map
  description = "map of tags to be applied to all resources"
  default     = {}
}

variable "terraform_version" {
  type        = string
  description = "Terraform version required by the target resources"
}

variable "resources_path" {
  type        = string
  description = "relative path of the target resources in the git repo"
  default     = "resources/"
}

variable "drift_cron" {
  type        = string
  description = "AWS EventBridge cron expression for when drift should be checked"
  default     = "cron(0 12 * * ? *)"
}

variable "resource_plan_policy_arns" {
  type        = list(string)
  description = "ARNs of IAM policies that support Terraform plan on the target resources"
}

variable "resource_apply_policy_arns" {
  type    = list(string)
  description = "ARNs of IAM policies that support Terraform apply on the target resources"
}

variable "github_webhook_enabled" {
  type        = bool
  description = "Should the plan/apply pipeline be run when commits are made to the target branch?"
  default     = false
}

variable "tf_log" {
  type        = string
  description = "value for the TF_LOG variable in Terraform plan/apply operations"
  default     = null
}

variable "log_retention_in_days" {
  type        = number
  description = "number of days to retain CodePipeline and CodeBuild logs"
  default     = 90
}

variable "notify_topic_tags" {
  type        = map(string)
  description = "tags to apply to the SNS topic used for notifications"
  default     = {}
}

variable  "alert_topic_tags" {
  type        = map(string)
  description = "tags to apply to the SNS topic used for alerts"
  default     = {}
}
