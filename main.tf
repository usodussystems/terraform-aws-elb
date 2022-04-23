locals {
  tags = {
    ModificationDate = timestamp()
    # Console | Terraform | Ansible | Packer
    Builder = "Terraform"
    # Client Infos
    Applictation = var.application
    Project      = var.project
    Environment  = local.environment[var.environment]
  }
  environment = {
    dev = "Development"
    prd = "Production"
    hml = "Homolog"
  }
  # name_pattern = format("%s-%s-%s", var.project, var.environment, local.resource)
  sg_alb_name   = format("%s-%s-%s", var.project, var.environment, "sg-alb")
  sg_intances_name     = format("%s-%s-%s", var.project, var.environment, "sg-instances")
  alb_name = format("%s-%s-%s", var.project, var.environment, "alb-frontend")
}

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}


/**
 * Main Securities Groups
 */
resource "aws_security_group" "private_instances" {
  name        = local.sg_intances_name
  vpc_id      = var.vpc_id
  description = "SG For private network"
  tags = merge(
    {
      "Name" = local.sg_intances_name
    },
    local.tags
  )
  ingress {
    from_port   = 0
    self = true
    protocol = "-1"
    to_port  = 0
    description = "Side Comm"
  }
  ingress {
    from_port   = 80
    description = "Client Ingress"
    cidr_blocks = var.subnet_private_cidrs
    protocol    = "tcp"
    to_port     = 80
  }
  ingress {
    from_port   = 443
    description = "Secured Client Ingress"
    cidr_blocks = var.subnet_private_cidrs
    protocol    = "tcp"
    to_port     = 443
  }
  ingress {
    from_port   = 22
    description = "SSH Ingress"
    cidr_blocks = var.subnet_private_cidrs
    protocol    = "tcp"
    to_port     = 22
  }

  egress {
    from_port   = 0
    description = "All tranfic out permited"
    cidr_blocks = [
    "0.0.0.0/0"]
    ipv6_cidr_blocks = [
    "::/0"]
    protocol = "-1"
    to_port  = 0
  }
}

resource "aws_security_group" "adm_lb_sg" {
  vpc_id = var.vpc_id
  name   = local.sg_alb_name

  # DNS que me provem um serviço tem um conjunto de IPs (CIDRs) 
  # que eles utilizam, o correto é a gente sempre definir 
  # que a origem da chamada deve ser desse IP
  ingress {
    description = "HTTP Communication for bastion"
    protocol    = "TCP"
    cidr_blocks = [
    "0.0.0.0/0"] 
    from_port = 80
    to_port   = 80
  }

  ingress {
    description = "HTTPS Communication for bastion"
    protocol    = "TCP"
    cidr_blocks = [
    "0.0.0.0/0"]
    from_port = 443
    to_port   = 443
  }

  egress {
    description = "Web Communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
    "0.0.0.0/0"]
  }

  tags = merge({
    Name = local.sg_alb_name
  }, local.tags)
}

/**
 * Load Balancer Application - Destination to main routes
 */
resource "aws_lb" "adm_lb" {
  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups = [
  aws_security_group.adm_lb_sg.id]
  subnets = var.public_subnet_ids

  enable_deletion_protection = var.environment == "prd"
  tags                       = local.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.adm_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = <<EOF
      <h1> "Sorry =(, this subdomain is not available! (@_@)" </h1>
EOF
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.adm_lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


/**
 * Domain 
 */

data "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_route53_record" "typeA_dev" {
  name    = var.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.main.zone_id

  alias {
    name                   = aws_lb.adm_lb.dns_name
    zone_id                = aws_lb.adm_lb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

/**
 * Certificate TLS
 */ 
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  subject_alternative_names = [
    format("*.%s", var.domain_name)
  ]
  tags = merge({
    Name = var.domain_name
  },
  local.tags)
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}