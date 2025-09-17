module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 5.6"

  cluster_name = var.name

  fargate_capacity_providers = {
    FARGATE      = {}
    FARGATE_SPOT = {}
  }

  tags = var.tags
}

module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.6"

  name        = var.name
  cluster_arn = module.ecs_cluster.arn

  cpu    = 1024
  memory = 2048

  # supports external task def deployments
  # by ignoring changes to task definition and desired count
  ignore_task_definition_changes = true
  desired_count                  = 1

  # Task Definition
  enable_execute_command = false

  container_definitions = {
    (var.container_name) = {

      image = var.image

      port_mappings = [
        {
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
          "value" : var.agentcore_runtime_arn
        },
        {
          "name" : "MEMORY_ID",
          "value" : var.agentcore_memory_id
        },
        {
          "name" : "ENABLE_AUTHENTICATION",
          "value" : tostring(var.enable_authentication)
        },
        {
          "name" : "COGNITO_LOGOUT_URL",
          "value" : var.enable_authentication ? coalesce(var.cognito_logout_url, "https://${aws_cognito_user_pool_domain.main[0].domain}.auth.${data.aws_region.current.name}.amazoncognito.com/logout?client_id=${aws_cognito_user_pool_client.main[0].id}&logout_uri=${var.acm_certificate_arn != "" ? "https" : "http"}://${module.alb.dns_name}") : ""
        },
      ]

      readonly_root_filesystem = false

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

  subnet_ids = module.vpc.private_subnets

  security_group_rules = {
    ingress_alb_service = {
      type                     = "ingress"
      from_port                = var.container_port
      to_port                  = var.container_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb.security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tasks_iam_role_name        = "${var.name}-tasks"
  tasks_iam_role_description = "role for ${var.name}"

  tasks_iam_role_statements = [
    {
      actions   = ["bedrock-agentcore:InvokeAgentRuntime"]
      resources = ["arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:runtime/*"]
    },
    {
      actions   = ["bedrock-agentcore:GetWorkloadAccessTokenForUserId"]
      resources = ["arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:workload-identity-directory/default/workload-identity/*"]
    },
    {
      actions = [
        "bedrock-agentcore:ListEvents",
        "bedrock-agentcore:ListSessions",
      ]
      resources = ["arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:memory/*"]
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

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name = var.name

  enable_deletion_protection = false

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  access_logs = var.alb_access_logs_enabled ? {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  } : {}

  connection_logs = var.alb_connection_logs_enabled ? {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  } : {}

  security_group_ingress_rules = merge(
    { for idx, ip in var.allowed_ips :
      "http_${idx}" => merge(
        {
          from_port   = 80
          to_port     = 80
          ip_protocol = "tcp"
          description = "HTTP web traffic from ${ip}"
        },
        strcontains(ip, ":") ? { cidr_ipv6 = ip } : { cidr_ipv4 = ip }
      )
    },
    var.acm_certificate_arn != "" ? { for idx, ip in var.allowed_ips :
      "https_${idx}" => merge(
        {
          from_port   = 443
          to_port     = 443
          ip_protocol = "tcp"
          description = "HTTPS web traffic from ${ip}"
        },
        strcontains(ip, ":") ? { cidr_ipv6 = ip } : { cidr_ipv4 = ip }
      )
    } : {}
  )

  security_group_egress_rules = merge(
    { for cidr_block in module.vpc.private_subnets_cidr_blocks :
      (cidr_block) => {
        ip_protocol = "-1"
        cidr_ipv4   = cidr_block
      }
    },
    {
      https_outbound = {
        from_port   = 443
        to_port     = 443
        ip_protocol = "tcp"
        cidr_ipv4   = "0.0.0.0/0"
        description = "HTTPS outbound for Cognito authentication"
      }
    }
  )

  listeners = merge(
    {
      http = merge(
        {
          port     = "80"
          protocol = "HTTP"
        },
        var.acm_certificate_arn != "" ? {
          redirect = {
            port        = "443"
            protocol    = "HTTPS"
            status_code = "HTTP_301"
          }
        } : var.enable_authentication ? {
          authenticate_cognito = {
            user_pool_arn       = aws_cognito_user_pool.main[0].arn
            user_pool_client_id = aws_cognito_user_pool_client.main[0].id
            user_pool_domain    = aws_cognito_user_pool_domain.main[0].domain
          }
          forward = {
            target_group_key = "ecs-task"
          }
        } : {
          forward = {
            target_group_key = "ecs-task"
          }
        }
      )
    },
    var.acm_certificate_arn != "" ? {
      https = merge(
        {
          port            = "443"
          protocol        = "HTTPS"
          certificate_arn = var.acm_certificate_arn
        },
        var.enable_authentication ? {
          authenticate_cognito = {
            user_pool_arn       = aws_cognito_user_pool.main[0].arn
            user_pool_client_id = aws_cognito_user_pool_client.main[0].id
            user_pool_domain    = aws_cognito_user_pool_domain.main[0].domain
          }
          forward = {
            target_group_key = "ecs-task"
          }
        } : {
          forward = {
            target_group_key = "ecs-task"
          }
        }
      )
    } : {}
  )

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
