
resource "aws_codepipeline" "drift-pipeline" {
  name     = "${var.namespace}-drift-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

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
        DetectChanges    = false
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = local.build_project_name_drift
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "build-drift" {
  name              = local.build_project_name_drift
  retention_in_days = var.log_retention_in_days
  tags              = var.global_tags
}

resource "aws_codebuild_project" "build-drift" {
  name          = local.build_project_name_drift
  build_timeout = "10"
  service_role  = aws_iam_role.build-role.arn
  tags          = var.global_tags

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = templatefile(
                  "${path.module}/buildspec.check-drift.tmpl.yml",
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
      group_name = local.build_project_name_drift
    }

    s3_logs {
      status   = "DISABLED"
      # location = "${aws_s3_bucket.codepipeline_bucket.id}/build-logs/apply"
    }
  }
}

#####################################################################
# cron for triggering pipeline
#####################################################################

resource "aws_cloudwatch_event_rule" "build-drift-trigger" {
  name                = "${local.build_project_name_drift}-trigger"
  description         = "Trigger daily drift check"
  schedule_expression = var.drift_cron
}

resource "aws_cloudwatch_event_target" "build-drift-trigger" {
  depends_on = [aws_cloudwatch_event_rule.build-drift-trigger]

  rule     = "${local.build_project_name_drift}-trigger"
  arn      = aws_codepipeline.drift-pipeline.arn
  role_arn = aws_iam_role.build-drift-pipeline-trigger-role.arn
}

#####################################################################
# IAM resources for CloudWatch resources
#####################################################################

resource "aws_iam_role" "build-drift-pipeline-trigger-role" {
  name = "${var.namespace}-build-drift-pipeline-trigger-role"
  tags = var.global_tags

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

resource "aws_iam_role_policy" "build-drift-trigger-policy" {
  role = aws_iam_role.build-drift-pipeline-trigger-role.name
  name = "build-drift-trigger-policy"

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "codepipeline:StartPipelineExecution"
            ],
            "Resource": [
                "${aws_codepipeline.drift-pipeline.arn}"
            ]
        }
    ]
}
POLICY

}

#####################################################################
# DRIFT Notifications based on pipeline process
#####################################################################

resource "aws_codestarnotifications_notification_rule" "drift-pipeline-notify" {
  detail_type    = "FULL"
  event_type_ids = [
    "codepipeline-pipeline-pipeline-execution-succeeded",
    "codepipeline-pipeline-pipeline-execution-started"
  ]

  name     = "${aws_codepipeline.drift-pipeline.name}-notify-teams"
  resource = aws_codepipeline.drift-pipeline.arn

  target {
    address = aws_sns_topic.notify-topic.arn
  }
}

resource "aws_codestarnotifications_notification_rule" "drift-pipeline-alert" {
  detail_type    = "FULL"
  event_type_ids = [
    "codepipeline-pipeline-pipeline-execution-failed",
    "codepipeline-pipeline-pipeline-execution-canceled",
    "codepipeline-pipeline-pipeline-execution-resumed",
    "codepipeline-pipeline-pipeline-execution-superseded"
  ]

  name     = "${aws_codepipeline.drift-pipeline.name}-alert-teams"
  resource = aws_codepipeline.drift-pipeline.arn

  target {
    address = aws_sns_topic.alert-topic.arn
  }
}
