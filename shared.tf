locals {
  build_project_name_base  = var.namespace
  build_project_name_drift = "${local.build_project_name_base}-drift"
  build_project_name_plan  = "${local.build_project_name_base}-plan"
  build_project_name_apply = "${local.build_project_name_base}-apply"
}

data "aws_caller_identity" "current" {
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "${var.namespace}-pipeline-resources"
  tags = merge(var.global_tags, {
    "cit:policy5.10-risk-level" = "medium"
  })
}

resource "aws_s3_bucket_public_access_block" "codepipeline_bucket" {
  bucket                  = aws_s3_bucket.codepipeline_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_bucket" {
  bucket = aws_s3_bucket.codepipeline_bucket.id

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "codepipeline_bucket" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  policy = data.aws_iam_policy_document.codepipeline_bucket.json
}

data "aws_iam_policy_document" "codepipeline_bucket" {
  statement {
    actions   = ["s3:*"]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.codepipeline_bucket.bucket}/*",
      "arn:aws:s3:::${aws_s3_bucket.codepipeline_bucket.bucket}"
    ]
    effect    = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "codepipeline_bucket" {
  bucket = aws_s3_bucket.codepipeline_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name = "${var.namespace}-pipeline-role"
  tags = var.global_tags

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${var.namespace}-pipeline-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "${aws_s3_bucket.codepipeline_bucket.arn}",
        "${aws_s3_bucket.codepipeline_bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codestar-connections:UseConnection"
      ],
      "Resource": "${data.aws_codestarconnections_connection.github.id}"
    } 
  ]
}
EOF

}

resource "aws_iam_role" "build-role" {
  name = "${var.namespace}-build-role"
  tags = var.global_tags

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

resource "aws_iam_role" "apply-role" {
  name = "${var.namespace}-apply-role"
  tags = var.global_tags

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

# resource "aws_iam_role_policy_attachment" "build-iam-read-only-policy-attach" {
#   role       = aws_iam_role.build-role.name
#   policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
# }

# resource "aws_iam_role_policy_attachment" "build-tag-read-only-policy-attach" {
#   role       = aws_iam_role.build-role.name
#   policy_arn = "arn:aws:iam::aws:policy/ResourceGroupsandTagEditorReadOnlyAccess"
# }

# resource "aws_iam_role_policy_attachment" "apply-cloudwatch-logs-admin-policy-attach" {
#   role       = aws_iam_role.apply-role.name
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
# }

# resource "aws_iam_role_policy_attachment" "apply-tag-admin-policy-attach" {
#   role       = aws_iam_role.apply-role.name
#   policy_arn = "arn:aws:iam::aws:policy/ResourceGroupsandTagEditorFullAccess"
# }

resource "aws_iam_policy" "build-policy" {
  name = "${var.namespace}-build-policy"
  tags= var.global_tags

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:ListTagsLogGroup",
        "logs:ListTagsForResource"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
      ],
      "Resource": [
        "${aws_s3_bucket.codepipeline_bucket.arn}",
        "${aws_s3_bucket.codepipeline_bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock"
    },
    {
        "Effect": "Allow",
        "Action": "s3:ListBucket",
        "Resource": "arn:aws:s3:::${var.terraform_state_bucket}"
    },
    {
        "Effect": "Allow",
        "Action": [
            "s3:GetObject",
            "s3:PutObject"
        ],
        "Resource": "arn:aws:s3:::${var.terraform_state_bucket}/${var.terraform_state_key}"
    },
    {
        "Sid": "IamReadPolicy",
        "Effect": "Allow",
        "Action": [
            "iam:GetPolicy",
            "iam:GetPolicyVersion"
        ],
        "Resource": ${jsonencode(var.resource_plan_policy_arns)}
    }
  ]
}
POLICY

}

resource "aws_iam_policy" "apply-policy" {
  name = "${var.namespace}-apply-policy"
  tags = var.global_tags

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:ListTagsLogGroup",
        "logs:ListTagsForResource"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
      ],
      "Resource": [
        "${aws_s3_bucket.codepipeline_bucket.arn}",
        "${aws_s3_bucket.codepipeline_bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock"
    },
    {
        "Effect": "Allow",
        "Action": "s3:ListBucket",
        "Resource": "arn:aws:s3:::${var.terraform_state_bucket}"
    },
    {
        "Effect": "Allow",
        "Action": [
            "s3:GetObject",
            "s3:PutObject"
        ],
        "Resource": "arn:aws:s3:::${var.terraform_state_bucket}/${var.terraform_state_key}"
    },
    {
        "Sid": "IamReadPolicy",
        "Effect": "Allow",
        "Action": [
            "iam:GetPolicy",
            "iam:GetPolicyVersion"
        ],
        "Resource": ${jsonencode(var.resource_plan_policy_arns)}
    }
  ]
}
POLICY

}

resource "aws_iam_role_policy_attachment" "build-policy-attach" {
  role       = aws_iam_role.build-role.name
  policy_arn = aws_iam_policy.build-policy.arn
}

resource "aws_iam_role_policy_attachment" "build-resource-policies" {
  count      = length(var.resource_plan_policy_arns)
  role       = aws_iam_role.build-role.name
  policy_arn = var.resource_plan_policy_arns[count.index]
}

resource "aws_iam_role_policy_attachment" "apply-policy-attach" {
  role       = aws_iam_role.apply-role.name
  policy_arn = aws_iam_policy.apply-policy.arn
}

resource "aws_iam_role_policy_attachment" "apply-resource-policies" {
  count      = length(var.resource_apply_policy_arns)
  role       = aws_iam_role.apply-role.name
  policy_arn = var.resource_apply_policy_arns[count.index]
}

#####################################################################
# Notifications based on build process
#####################################################################

resource "aws_cloudwatch_event_rule" "build-failure" {
  name        = "${local.build_project_name_base}-build-failure"
  description = "Send notifications upon build failure"

  event_pattern = <<PATTERN
{
  "source": [
    "aws.codebuild"
  ],
  "detail-type": [
    "CodeBuild Build Phase Change"
  ],
  "detail": {
    "completed-phase-status": [
      "TIMED_OUT",
      "STOPPED",
      "FAILED",
      "FAULT",
      "CLIENT_ERROR"
    ],
    "project-name": [
      "${local.build_project_name_plan}",
      "${local.build_project_name_drift}",
      "${local.build_project_name_apply}"
    ]
  }
}
PATTERN

}

resource "aws_cloudwatch_event_target" "build-failure" {
  depends_on = [aws_cloudwatch_event_rule.build-failure]

  rule = "${local.build_project_name_base}-build-failure"
  arn  = aws_sns_topic.notify-topic.arn
  input_transformer {
    input_paths = {
      date    = "$.detail.additional-information.build-start-time"
      phase   = "$.detail.completed-phase"
      loglink = "$.detail.additional-information.logs.deep-link"
      project = "$.detail.project-name"
      error   = "$.detail.completed-phase-context"
      status  = "$.detail.completed-phase-status"
    }
    input_template = <<TEMPLATE
"<date> <project> - State: <status> Phase: <phase> Error: <error> Link: <loglink> "
TEMPLATE

  }
}

data "aws_codestarconnections_connection" "github" {
  arn = var.github_codestarconnections_connection_arn
}
