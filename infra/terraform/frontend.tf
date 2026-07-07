locals {
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
  frontend_site_url = local.frontend_cloudfront_enabled ? module.frontend_cloudfront[0].hosted_url : (
    var.enable_amplify ? try("https://${module.amplify[0].default_domain}", "") : ""
  )
  frontend_callback_url = local.frontend_site_url != "" ? "${local.frontend_site_url}/auth/callback" : ""
  frontend_logout_url   = local.frontend_site_url != "" ? "${local.frontend_site_url}/account" : ""
  effective_cognito_callback_urls = distinct(concat(
    var.cognito_callback_urls,
    compact([local.frontend_callback_url]),
  ))
  effective_cognito_logout_urls = distinct(concat(
    var.cognito_logout_urls,
    compact([local.frontend_logout_url]),
  ))
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
