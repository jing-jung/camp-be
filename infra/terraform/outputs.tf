output "api_base_url" {
  description = "API Gateway invoke URL for the FastAPI Lambda target."
  value       = module.api_lambda.api_base_url
}

output "amplify_app_id" {
  description = "Amplify app id."
  value       = try(module.amplify[0].app_id, "")
}

output "amplify_default_domain" {
  description = "Amplify default domain for the web app."
  value       = try(module.amplify[0].default_domain, "")
}

output "frontend_ecr_repository_url" {
  description = "ECR repository URL for the frontend container image."
  value       = try(module.frontend_ecs[0].ecr_repository_url, "")
}

output "frontend_ecs_cluster_name" {
  description = "ECS cluster name for the frontend service."
  value       = try(module.frontend_ecs[0].cluster_name, "")
}

output "frontend_ecs_service_name" {
  description = "ECS service name for the frontend."
  value       = try(module.frontend_ecs[0].service_name, "")
}

output "frontend_alb_dns_name" {
  description = "ALB DNS name for the frontend service."
  value       = try(module.frontend_ecs[0].alb_dns_name, "")
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution id for the hosted frontend."
  value       = try(module.frontend_cloudfront_lambda[0].cloudfront_distribution_id, try(module.frontend_cloudfront[0].distribution_id, ""))
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name for the hosted frontend."
  value       = try(module.frontend_cloudfront_lambda[0].cloudfront_domain_name, try(module.frontend_cloudfront[0].domain_name, ""))
}

output "frontend_hosted_url" {
  description = "HTTPS URL for the hosted frontend."
  value       = local.frontend_site_url
}

output "frontend_lambda_function_name" {
  description = "Lambda function name for the serverless frontend."
  value       = try(module.frontend_lambda[0].lambda_function_name, "")
}

output "frontend_lambda_function_url" {
  description = "Lambda Function URL for the serverless frontend."
  value       = try(module.frontend_lambda[0].function_url, "")
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint."
  value       = var.enable_elasticache ? try(module.elasticache[0].redis_endpoint, "") : ""
}

output "waf_web_acl_id" {
  description = "WAF Web ACL ID."
  value       = var.enable_waf ? try(module.waf[0].web_acl_id, "") : ""
}

output "monitoring_dashboard_url" {
  description = "CloudWatch dashboard URL for monitoring."
  value       = var.enable_enhanced_monitoring ? try(module.monitoring[0].dashboard_url, "") : ""
}

output "monitoring_sns_topic_arn" {
  description = "SNS topic ARN for alerts."
  value       = var.enable_enhanced_monitoring ? try(module.monitoring[0].sns_topic_arn, "") : ""
}

output "database_secret_arn" {
  description = "Secrets Manager ARN used by Lambda for database connection material."
  value       = module.rds.db_secret_arn
  sensitive   = true
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint used by Lambda when enable_rds_proxy is true."
  value       = module.rds_proxy.proxy_endpoint
}

output "rds_endpoint" {
  description = "RDS endpoint used by Lambda when RDS Proxy is disabled."
  value       = module.rds.db_endpoint
}

output "external_api_secret_arn" {
  description = "Secrets Manager ARN for OpenDART/NAVER API credentials."
  value       = module.secrets.external_api_secret_arn
  sensitive   = true
}

output "ingestion_raw_bucket_name" {
  description = "S3 bucket used for raw provider ingestion payload archives."
  value       = try(aws_s3_bucket.ingestion_raw[0].bucket, "")
}

output "ingestion_raw_kms_key_arn" {
  description = "KMS key ARN used for S3 raw provider ingestion payload archives."
  value       = try(aws_kms_key.ingestion_raw[0].arn, "")
}

output "ingestion_dlq_url" {
  description = "SQS DLQ URL for failed scheduled ingestion invocations."
  value       = aws_sqs_queue.ingestion_dlq.url
}

output "ingestion_scheduler_name" {
  description = "Comma-separated EventBridge Scheduler names for provider ingestion when enabled."
  value       = length(aws_scheduler_schedule.provider_ingestion) > 0 ? join(",", [for schedule in values(aws_scheduler_schedule.provider_ingestion) : schedule.name]) : ""
}

output "ingestion_scheduler_names" {
  description = "EventBridge Scheduler names for provider ingestion when enabled."
  value       = [for schedule in values(aws_scheduler_schedule.provider_ingestion) : schedule.name]
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool id for email-based P1 auth."
  value       = module.cognito.user_pool_id
}

output "cognito_app_client_id" {
  description = "Public Cognito app client id for the Next.js frontend."
  value       = module.cognito.app_client_id
}

output "cognito_issuer" {
  description = "JWT issuer used by API Gateway HTTP API authorizer."
  value       = module.cognito.issuer
}

output "cognito_hosted_ui_domain" {
  description = "Cognito Hosted UI HTTPS URL for the Next.js frontend."
  value = module.cognito.hosted_ui_domain == "" ? "" : (
    "https://${module.cognito.hosted_ui_domain}.auth.${var.aws_region}.amazoncognito.com"
  )
}

output "agentcore_runtime_arn" {
  description = "AgentCore Runtime ARN when agentcore_runtime_enabled is true."
  value       = module.agentcore_runtime.runtime_arn
}

output "agentcore_runtime_endpoint_name" {
  description = "AgentCore Runtime default endpoint name when enabled."
  value       = module.agentcore_runtime.runtime_endpoint_name
}
