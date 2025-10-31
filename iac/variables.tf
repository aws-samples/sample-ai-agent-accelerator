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
