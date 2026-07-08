locals {
  # ECS-based frontend (legacy)
  frontend_ecs_subnet_ids = length(var.frontend_ecs_subnet_ids) > 0 ? var.frontend_ecs_subnet_ids : var.frontend_alb_subnet_ids
  frontend_ecs_enabled = (
    var.enable_frontend_ecs &&
    var.vpc_id != "" &&
    length(var.frontend_alb_subnet_ids) > 0 &&
    length(local.frontend_ecs_subnet_ids) > 0
  )
  frontend_cloudfront_enabled = (
    var.enable_frontend_cloudfront &&
    local.frontend_ecs_enabled &&
    var.frontend_rendering_mode == "container"
  )

  # Lambda-based frontend (serverless)
  frontend_lambda_enabled = (
    var.enable_frontend_lambda &&
    var.frontend_container_image != ""
  )
  frontend_cloudfront_lambda_enabled = (
    var.enable_frontend_cloudfront_lambda &&
    local.frontend_lambda_enabled
  )

  # Determine frontend URL
  frontend_site_url = (
    local.frontend_cloudfront_lambda_enabled ? module.frontend_cloudfront_lambda[0].hosted_url :
    local.frontend_cloudfront_enabled ? module.frontend_cloudfront[0].hosted_url :
    var.enable_amplify ? try("https://${module.amplify[0].default_domain}", "") : ""
  )
  frontend_callback_url = local.frontend_site_url != "" ? "${local.frontend_site_url}/auth/callback" : ""
  frontend_logout_url   = local.frontend_site_url != "" ? "${local.frontend_site_url}/account" : ""
  # Cycle prevention: Do not automatically inject frontend_site_url into Cognito
  # You must add the generated CloudFront URL to cognito_callback_urls in tfvars manually after the first deployment.
  effective_cognito_callback_urls = var.cognito_callback_urls
  effective_cognito_logout_urls   = var.cognito_logout_urls
  effective_cors_allowed_origins = join(",", distinct(compact(concat(
    [for origin in split(",", var.cors_allowed_origins) : trimspace(origin) if trimspace(origin) != ""],
    local.frontend_site_url != "" ? [local.frontend_site_url] : [],
  ))))
}

module "frontend_ecs" {
  count  = local.frontend_ecs_enabled ? 1 : 0
  source = "./modules/frontend_ecs"

  name_prefix          = local.name_prefix
  vpc_id               = var.vpc_id
  alb_subnet_ids       = var.frontend_alb_subnet_ids
  ecs_subnet_ids       = local.frontend_ecs_subnet_ids
  assign_public_ip     = var.frontend_assign_public_ip
  desired_count        = var.frontend_desired_count
  container_image      = var.frontend_container_image
  image_tag            = var.frontend_image_tag
  cpu                  = var.frontend_cpu
  memory               = var.frontend_memory
  environment_variables = {
    NODE_ENV = "production"
    PORT     = "3000"
    HOSTNAME = "0.0.0.0"
  }
}

module "frontend_cloudfront" {
  count  = local.frontend_cloudfront_enabled ? 1 : 0
  source = "./modules/frontend_cloudfront"

  name_prefix     = local.name_prefix
  rendering_mode  = var.frontend_rendering_mode
  alb_dns_name    = module.frontend_ecs[0].alb_dns_name
}

# Lambda Web Adapter-based Frontend (Serverless)
module "frontend_lambda" {
  count  = local.frontend_lambda_enabled ? 1 : 0
  source = "./modules/frontend_lambda"

  name_prefix               = local.name_prefix
  container_image           = var.frontend_container_image
  image_tag                 = var.frontend_image_tag
  memory_mb                 = var.frontend_lambda_memory_mb
  timeout_seconds           = var.frontend_lambda_timeout_seconds
  reserved_concurrent_executions = var.frontend_lambda_reserved_concurrent_executions
  log_retention_days        = var.frontend_lambda_log_retention_days

  environment_variables = merge(
    var.frontend_lambda_environment_variables,
    {
      NEXT_PUBLIC_API_BASE = module.api_lambda.api_base_url
    }
  )
}

module "frontend_cloudfront_lambda" {
  count  = local.frontend_cloudfront_lambda_enabled ? 1 : 0
  source = "./modules/frontend_cloudfront_lambda"

  name_prefix = local.name_prefix
  function_url = module.frontend_lambda[0].function_url
  price_class = var.frontend_cloudfront_price_class
  default_ttl = var.frontend_cloudfront_default_ttl
  max_ttl     = var.frontend_cloudfront_max_ttl
}
