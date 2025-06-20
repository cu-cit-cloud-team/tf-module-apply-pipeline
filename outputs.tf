output "notifications_sns_topic_arn" {
  value = aws_sns_topic.notify-topic.arn
  description = "ARN of SNS topic where normal CodePipeline and CodeBuild notifications are sent"
}

output "alerts_sns_topic_arn" {
  value = aws_sns_topic.alert-topic.arn
  description = "ARN of SNS topic where abnormal CodePipeline and CodeBuild notifications are sent"
}
