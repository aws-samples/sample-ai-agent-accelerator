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
  value       = local.data_source_id
}

output "s3_bucket_name" {
  description = "The name of the s3 bucket that was created"
  value       = aws_s3_bucket.main.bucket
}

output "agentcore_runtime_arn" {
  description = "The ARN of the AgentCore runtime"
  value       = aws_bedrockagentcore_agent_runtime.main.agent_runtime_arn
}

output "agentcore_memory_id" {
  description = "The ID of the AgentCore memory"
  value       = aws_bedrockagentcore_memory.main.id
}

output "agentcore_ecr_repository_url" {
  description = "The URL of the AgentCore ECR repository"
  value       = aws_ecr_repository.agent.repository_url
}
