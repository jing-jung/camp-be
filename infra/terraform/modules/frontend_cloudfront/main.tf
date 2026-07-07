locals {
  origin_id = var.rendering_mode == "container" ? "ecs-alb" : "static-s3"
}

resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  comment             = "${var.name_prefix} frontend"
  default_root_object = ""
  price_class         = var.price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  origin {
    domain_name = var.alb_dns_name
    origin_id   = local.origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

    default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin", "Authorization", "Accept", "Accept-Language", "CloudFront-Forwarded-Proto"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = var.enable_caching ? var.min_ttl : 0
    default_ttl = var.enable_caching ? var.default_ttl : 0
    max_ttl     = var.enable_caching ? var.max_ttl : 0
  }

  # Static assets caching (CSS, JS, images, fonts)
  ordered_cache_behavior {
    path_pattern           = "/_next/static/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 31536000  # 1 year
    max_ttl     = 31536000  # 1 year
  }

  # Public static assets (images, etc.)
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400     # 24 hours
    max_ttl     = 31536000  # 1 year
  }

  # API routes - no caching
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin", "Authorization", "Accept", "Accept-Language", "CloudFront-Forwarded-Proto"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.name_prefix}-frontend"
  }
}
