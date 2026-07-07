output "ecr_repository_url" {
  description = "ECR repository URL for frontend container images."
  value       = aws_ecr_repository.web.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name for frontend container images."
  value       = aws_ecr_repository.web.name
}

output "cluster_name" {
  description = "ECS cluster name for the frontend service."
  value       = aws_ecs_cluster.web.name
}

output "service_name" {
  description = "ECS service name for the frontend."
  value       = aws_ecs_service.web.name
}

output "alb_dns_name" {
  description = "Internet-facing ALB DNS name for the frontend service."
  value       = aws_lb.web.dns_name
}

output "alb_arn" {
  description = "Internet-facing ALB ARN for the frontend service."
  value       = aws_lb.web.arn
}

output "alb_zone_id" {
  description = "Route53 zone id for the frontend ALB."
  value       = aws_lb.web.zone_id
}

output "target_group_arn" {
  description = "ALB target group ARN for the frontend service."
  value       = aws_lb_target_group.web.arn
}
