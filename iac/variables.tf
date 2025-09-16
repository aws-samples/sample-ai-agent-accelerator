variable "name" {
  description = "The name of this template (e.g., my-app-prod)"
  type        = string
}

variable "region" {
  description = "The AWS region to deploy to (e.g., us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "container_name" {
  description = "The name of the container"
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "The port that the container is listening on"
  type        = number
  default     = 8080
}

variable "health_check" {
  description = "A map containing configuration for the health check"
  type        = string
  default     = "/health"
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "image" {
  description = "container image to initially bootstrap. future images can be deployed using a separate mechanism"
  type        = string
  default     = "public.ecr.aws/jritsema/defaultbackend"
}

variable "agentcore_runtime_arn" {
  description = "ARN of the AgentCore Runtime we want to use"
  type        = string
  default     = ""
}

variable "agentcore_memory_id" {
  description = "AgentCore memory id"
  type        = string
  default     = ""
}

variable "allowed_ips" {
  description = "List of IP addresses/CIDR blocks allowed to access the web interface"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS listener"
  type        = string
  default     = ""
}

variable "alb_access_logs_enabled" {
  description = "Enable ALB access logs"
  type        = bool
  default     = false
}

variable "alb_connection_logs_enabled" {
  description = "Enable ALB connection logs"
  type        = bool
  default     = false
}

variable "enable_authentication" {
  description = "Enable ALB+Cognito authentication"
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_authentication || var.acm_certificate_arn != ""
    error_message = "SSL/TLS certificate (acm_certificate_arn) is required when authentication is enabled. ALB authentication requires HTTPS for security."
  }
}

variable "cognito_logout_url" {
  description = "Custom Cognito logout URL (overrides default constructed URL)"
  type        = string
  default     = null
}
