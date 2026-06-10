output "runtime_arn" {
  value = try(aws_cloudformation_stack.runtime[0].outputs.RuntimeArn, "")
}

output "runtime_id" {
  value = try(aws_cloudformation_stack.runtime[0].outputs.RuntimeId, "")
}

output "runtime_endpoint_name" {
  value = try(aws_cloudformation_stack.runtime[0].outputs.RuntimeEndpointName, "")
}
