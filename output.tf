// s3 arn
output "webs3_arn" {
    value = aws_s3_bucket.webs3.arn
}

// GitHubActionsS3Access IAM Role arn
output "github_actions_s3_access" {
    value = aws_iam_role.github_actions_s3_access.arn
}