output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix (`app/<name>/<id>`) — used as the LoadBalancer dimension on AWS/ApplicationELB CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "DNS name (CNAME target for Route 53 alias records)."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone id of the ALB — used by Route 53 alias records."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ALB SG. Target SGs should allow ingress only from this SG."
  value       = aws_security_group.this.id
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener — attach rules here for path/host routing."
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (null if enable_https = false)."
  value       = try(aws_lb_listener.https[0].arn, null)
}
