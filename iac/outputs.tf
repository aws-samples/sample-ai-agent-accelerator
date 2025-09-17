output "name" {
  description = "The name of the application"
  value       = var.name
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "ecs_cluster_name" {
  description = "The name of the ecs cluster that was created or referenced"
  value       = module.ecs_cluster.name
}

output "ecs_cluster_arn" {
  description = "The arn of the ecs cluster that was created or referenced"
  value       = module.ecs_cluster.arn
}

output "ecs_service_name" {
  description = "The arn of the fargate ecs service that was created"
  value       = module.ecs_service.name
}

output "lb_arn" {
  description = "The arn of the load balancer"
  value       = module.alb.arn
}

output "lb_dns" {
  description = "The load balancer DNS name"
  value       = module.alb.dns_name
}

output "endpoint" {
  description = "The web application endpoint"
  value       = "http://${module.alb.dns_name}"
}

output "bedrock_knowledge_base_id" {
  description = "the id of the created bedrock knowledge base"
  value       = local.knowledge_base_id
}

output "bedrock_knowledge_base_data_source_id" {
  description = "the id of the created bedrock knowledge base data source"
  value       = aws_bedrockagent_data_source.main.data_source_id
}

output "s3_bucket_name" {
  description = "The name of the s3 bucket that was created"
  value       = aws_s3_bucket.main.bucket
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = var.enable_authentication ? aws_cognito_user_pool.main[0].id : null
}

output "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = var.enable_authentication ? aws_cognito_user_pool_client.main[0].id : null
}

output "cognito_domain" {
  description = "Cognito Domain for authentication"
  value       = var.enable_authentication ? "https://${aws_cognito_user_pool_domain.main[0].domain}.auth.${data.aws_region.current.name}.amazoncognito.com" : null
}

output "alb_logs_bucket_name" {
  description = "The name of the S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.bucket
}