variable "project" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "environment" {
  description = "The environment, and also used as a identifier"
  type        = string
  validation {
    condition     = try(length(regex("dev|prd|hml", var.environment)) > 0,false)
    error_message = "Define envrionment as one that follows: dev, hml or prd."
  }
}

variable "region" {
  description = "Region AWS where deploy occurs"
  type        = string
  default     = "us-east-1"
}

variable "application" {
  type = string
  description = "Name application"
}

########################################

variable "subnet_private_cidrs" {
  type = list(string)
  default = [ 
    "192.168.0.0/24",
  ]
}

variable "public_subnet_ids" {
  type = list(string)
  description = "List of public subnets for usage as definition for ALB"
}

variable "domain_name" {
  type = string
  description = "Domain name to be used for validation"
  default = "reymaster.dev.br"
}

variable "vpc_id" {
  type = string
  description = "VPC for security group attachment. Should be an ID"
}