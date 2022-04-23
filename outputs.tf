output "sg_instances_id" {
  description = "Generic Security Grop ID for instances in private subnet"
  value = aws_security_group.private_instances.id
}

output "alb_properties" {
  description = "ALB properties exposed"
  value = aws_lb.adm_lb
}

output "acm_arn" {
  description = "Certification for main domain"
  value = aws_acm_certificate.cert.arn
}

