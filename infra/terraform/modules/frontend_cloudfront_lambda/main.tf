locals {
  # Extract domain from Lambda Function URL
  # Example: abc123.lambda-url.ap-northeast-2.on.aws
  function_url_domain = replace(replace(var.function_url, "https://", ""), "/", "")
}

# CloudFront Origin Request Policy for Lambda Function URL
resource "aws_cloudfront_origin_request_policy" "lambda_function_url" {
  name = "${var.name_prefix}-lambda-function-url-policy"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allViewer"
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# CloudFront Cache Policy (no caching for SSR)
resource "aws_cloudfront_cache_policy" "no_cache" {
  name        = "${var.name_prefix}-no-cache-policy"
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  price_class         = var.price_class
  comment             = "${var.name_prefix} Frontend (Lambda Web Adapter)"
  default_root_object = ""

  origin {
    domain_name = local.function_url_domain
    origin_id   = "lambda-function-url"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "lambda-function-url"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = aws_cloudfront_cache_policy.no_cache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.lambda_function_url.id
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
    Name = "${var.name_prefix}-frontend-cloudfront"
  }
}
