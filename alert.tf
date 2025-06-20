resource "aws_sns_topic" "alert-topic" {
  name = "${local.build_project_name_base}-alert"

  tags = merge(
    var.global_tags,
    var.alert_topic_tags,
  )
}

resource "aws_sns_topic_policy" "alert-default" {
  arn = aws_sns_topic.alert-topic.arn

  policy = data.aws_iam_policy_document.alert-sns-topic-policy.json
}

data "aws_iam_policy_document" "alert-sns-topic-policy" {
  policy_id = "__default_policy_ID"

  statement {
    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      aws_sns_topic.alert-topic.arn,
    ]

    sid = "__default_statement_ID"
  }

  statement {
    actions = ["sns:Publish"]
    effect  = "Allow"
    sid     = "allow-cloudwatch-events-to-publish"
    resources = [
      aws_sns_topic.alert-topic.arn,
    ]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
  
  statement {
    actions = ["sns:Publish"]
    effect  = "Allow"
    sid     = "CodeNotification_publish"
    resources = [
      aws_sns_topic.alert-topic.arn,
    ]
    principals {
      type        = "Service"
      identifiers = ["codestar-notifications.amazonaws.com"]
    }
  }
}
