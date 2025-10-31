module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 6.0"

  name = var.name
  tags = var.tags
}

module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 6.0"

  name        = var.name
  cluster_arn = module.ecs_cluster.arn

  cpu    = 1024
  memory = 2048

  runtime_platform = {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  ignore_task_definition_changes = false
  desired_count                  = 1

  # Task Definition
  enable_execute_command = false

  container_definitions = {
    (var.container_name) = {

      image = docker_registry_image.web.name

      portMappings = [
        {
          name          = "http",
          protocol      = "tcp",
          containerPort = var.container_port
        }
      ]

      environment = [
        {
          "name" : "PORT",
          "value" : var.container_port
        },
        {
          "name" : "HEALTHCHECK",
          "value" : var.health_check
        },
        {
          "name" : "OTEL_RESOURCE_ATTRIBUTES",
          "value" : "service.namespace=${var.name},service.name=orchestrator"
        },
        {
          "name" : "AGENT_RUNTIME",
          "value" : aws_bedrockagentcore_agent_runtime.main.agent_runtime_arn
        },
        {
          "name" : "MEMORY_ID",
          "value" : aws_bedrockagentcore_memory.main.id
        },
      ]

      readonlyRootFilesystem = false

      dependsOn = [
        {
          containerName = "otel"
          condition     = "HEALTHY"
        }
      ]
    },
    otel = {
      image   = "public.ecr.aws/aws-observability/aws-otel-collector:v0.41.2"
      command = ["--config=/etc/ecs/ecs-default-config.yaml"]
      healthCheck = {
        command     = ["/healthcheck"]
        interval    = 5
        timeout     = 6
        retries     = 5
        startPeriod = 1
      }
    },
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["ecs-task"].arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.ecs_service.id]

  tasks_iam_role_name        = "${var.name}-tasks"
  tasks_iam_role_description = "role for ${var.name}"

  tasks_iam_role_statements = [
    {
      actions = [
        "bedrock-agentcore:InvokeAgentRuntime",
        "bedrock-agentcore:InvokeAgentRuntimeForUser"
      ]
      resources = ["arn:aws:bedrock-agentcore:${local.region_account}:runtime/*"]
    },
    {
      actions   = ["bedrock-agentcore:GetWorkloadAccessTokenForUserId"]
      resources = ["arn:aws:bedrock-agentcore:${local.region_account}:workload-identity-directory/default/workload-identity/*"]
    },
    {
      actions = [
        "bedrock-agentcore:ListEvents",
        "bedrock-agentcore:ListSessions",
      ]
      resources = ["arn:aws:bedrock-agentcore:${local.region_account}:memory/*"]
    },
    {
      actions = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ]
      resources = ["*"]
    },
  ]

  tags = var.tags
}

resource "aws_security_group" "ecs_service" {
  name_prefix = "${var.name}-ecs-service"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    description     = "Service port"
    security_groups = [module.alb.security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name = var.name

  enable_deletion_protection = false

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = { for cidr_block in module.vpc.private_subnets_cidr_blocks :
    (cidr_block) => {
      ip_protocol = "-1"
      cidr_ipv4   = cidr_block
    }
  }

  listeners = {
    http = {
      port     = "80"
      protocol = "HTTP"

      forward = {
        target_group_key = "ecs-task"
      }
    }
  }

  target_groups = {

    ecs-task = {
      backend_protocol = "HTTP"
      backend_port     = var.container_port
      target_type      = "ip"

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 10
        matcher             = "200-299"
        path                = var.health_check
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }
  }

  tags = var.tags
}
