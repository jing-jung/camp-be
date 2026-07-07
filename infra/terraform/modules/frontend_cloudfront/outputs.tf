output "distribution_id" {
  description = "CloudFront distribution id."
  value       = aws_cloudfront_distribution.web.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.web.arn
}

output "domain_name" {
  description = "CloudFront distribution domain name."
  value       = aws_cloudfront_distribution.web.domain_name
}

output "hosted_url" {
  description = "HTTPS URL for the hosted frontend."
  value       = "https://${aws_cloudfront_distribution.web.domain_name}"
}
