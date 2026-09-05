output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "app_role_name" {
  value = aws_iam_role.app.name
}

output "ci_role_arn" {
  value = aws_iam_role.ci.arn
}
