resource "aws_ecr_repository" "web" {
  name                 = "${var.name}-web"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# Build and push web app Docker image
resource "docker_image" "web" {
  name = "${aws_ecr_repository.web.repository_url}:${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  build {
    context    = "../"
    dockerfile = "Dockerfile.ci"
    platform   = "linux/arm64"
  }

  triggers = {
    timestamp = timestamp()
  }
}

resource "docker_registry_image" "web" {
  name = docker_image.web.name
}

# ECR repository for AgentCore runtime
resource "aws_ecr_repository" "agent" {
  name = "${var.name}-agent"

  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# Build and push Docker image
resource "docker_image" "agent" {
  name = "${aws_ecr_repository.agent.repository_url}:${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  build {
    context  = "../agent"
    platform = "linux/arm64"
  }

  triggers = {
    timestamp = timestamp()
  }
}

resource "docker_registry_image" "agent" {
  name = docker_image.agent.name
}
