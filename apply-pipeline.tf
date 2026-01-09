
resource "aws_codepipeline" "apply-pipeline" {
  name     = "${var.namespace}-apply-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn
  tags     = var.global_tags

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = data.aws_codestarconnections_connection.github.id
        FullRepositoryId = var.github_repo
        BranchName       = var.git_branch
        DetectChanges    = var.github_webhook_enabled
      }
    }
  }

  stage {
    name = "Plan"

    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["plan_output"]
      version          = "1"

      configuration = {
        ProjectName = local.build_project_name_plan
      }
    }
  }

  stage {
    name = "Approval"

    action {
      name     = "Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn    = aws_sns_topic.alert-topic.arn
      }
    }
  }

  stage {
    name = "Apply"

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output", "plan_output"]
      version         = "1"

      configuration = {
        ProjectName   = local.build_project_name_apply
        PrimarySource = "source_output"
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "build-plan" {
  name              = local.build_project_name_plan
  retention_in_days = var.log_retention_in_days
  tags              = var.global_tags
}

resource "aws_cloudwatch_log_group" "build-apply" {
  name              = local.build_project_name_apply
  retention_in_days = var.log_retention_in_days
  tags              = var.global_tags
}

resource "aws_codebuild_project" "build-plan" {
  name          = local.build_project_name_plan
  build_timeout = "10"
  service_role  = aws_iam_role.build-role.arn
  tags          = var.global_tags

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    # image                       = "aws/codebuild/standard:1.0"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = templatefile(
                  "${path.module}/buildspec.plan.tmpl.yml",
                  {
                    TERRAFORM_VERSION = var.terraform_version
                    RESOURCES_PATH    = var.resources_path
                    tf_log            = var.tf_log
                    SCRIPTS_LOCATION  = "s3://${aws_s3_bucket.codepipeline_bucket.id}/${local.scripts_prefix}/"
                  }
                )
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
      group_name = local.build_project_name_plan
    }

    s3_logs {
      status   = "DISABLED"
      # location = "${aws_s3_bucket.codepipeline_bucket.id}/build-logs/apply"
    }
  }

}

resource "aws_codebuild_project" "build-apply" {
  name          = local.build_project_name_apply
  build_timeout = "10"
  service_role  = aws_iam_role.apply-role.arn
  tags              = var.global_tags

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    # image                       = "aws/codebuild/standard:1.0"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = templatefile(
                  "${path.module}/buildspec.apply.tmpl.yml",
                  {
                    TERRAFORM_VERSION = var.terraform_version
                    RESOURCES_PATH    = var.resources_path
                    tf_log            = var.tf_log
                  }
                )
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
      group_name = local.build_project_name_apply
    }

    s3_logs {
      status   = "DISABLED"
      # location = "${aws_s3_bucket.codepipeline_bucket.id}/build-logs/apply"
    }
  }
}

#####################################################################
# APPLY Notifications based on pipeline process
#####################################################################

resource "aws_codestarnotifications_notification_rule" "apply-pipeline-notify" {
  detail_type    = "FULL"
  event_type_ids = [
    "codepipeline-pipeline-pipeline-execution-succeeded",
    "codepipeline-pipeline-pipeline-execution-started"
  ]

  name     = "${aws_codepipeline.apply-pipeline.name}-notify-teams"
  resource = aws_codepipeline.apply-pipeline.arn
  tags     = var.global_tags

  target {
    address = aws_sns_topic.notify-topic.arn
  }
}

resource "aws_codestarnotifications_notification_rule" "apply-pipeline-alert" {
  detail_type    = "FULL"
  event_type_ids = [
    "codepipeline-pipeline-pipeline-execution-failed",
    "codepipeline-pipeline-pipeline-execution-canceled",
    "codepipeline-pipeline-pipeline-execution-resumed",
    "codepipeline-pipeline-pipeline-execution-superseded",
  ]

  name     = "${aws_codepipeline.apply-pipeline.name}-alert-teams"
  resource = aws_codepipeline.apply-pipeline.arn
  tags     = var.global_tags

  target {
    address = aws_sns_topic.alert-topic.arn
  }
}

# Standard CodePipeline Notifications do not include STOPPED state,
# so we add a custom CloudWatch Event Rule and Target

resource "aws_cloudwatch_event_rule" "apply_pipeline_stopped" {
  name        = "${aws_codepipeline.apply-pipeline.name}-stopped"
  description = "Notify when a CodePipeline execution is stopping or stopped"

  event_pattern = jsonencode({
    "source"      : ["aws.codepipeline"],
    "detail-type" : ["CodePipeline Pipeline Execution State Change"],
    "detail" : {
      "pipeline" : [aws_codepipeline.apply-pipeline.name],
      "state"    : ["STOPPED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "apply_pipeline_stopped" {
  rule      = aws_cloudwatch_event_rule.apply_pipeline_stopped.name
  target_id = "notify-topic"
  arn       = aws_sns_topic.notify-topic.arn

  # This formats the message using AWS Chatbot custom message format
  input_transformer {
    input_paths = {
      region        = "$.region"
      pipeline      = "$.detail.pipeline"
      execution_id  = "$.detail.execution-id"
      state         = "$.detail.state"
      time          = "$.time"
      account       = "$.account"
    }

    input_template = <<-EOF
{
  "version":"1.0",
  "source":"custom",
  "content": {
    "textType":"client-markdown",
    "title":"AWS CodePipeline Notification | <region> | Account: <account>",
    "description":"CodePipeline pipeline execution **<state>**.\n- *Pipeline*: <pipeline>\n- *Execution ID*: <execution_id>\n- *Time*: <time>"
  }
}
EOF
  }
}
