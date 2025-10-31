# AgentCore Memory
resource "aws_bedrockagentcore_memory" "main" {
  name                  = var.name
  description           = "memory for ${var.name}"
  event_expiry_duration = 30

  tags = var.tags
}

# AgentCore Agent Runtime
resource "aws_bedrockagentcore_agent_runtime" "main" {
  agent_runtime_name = var.name
  role_arn           = aws_iam_role.agentcore_runtime.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = docker_registry_image.agent.name
    }
  }

  environment_variables = {
    APP_NAME          = var.name
    KNOWLEDGE_BASE_ID = local.knowledge_base_id
    MEMORY_ID         = aws_bedrockagentcore_memory.main.id
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy.agentcore_runtime]
}

# IAM role for AgentCore runtime
resource "aws_iam_role" "agentcore_runtime" {
  name = "${var.name}-AgentRuntimeRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeRolePolicy"
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:bedrock-agentcore:${local.region_account}:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for AgentCore runtime
resource "aws_iam_role_policy" "agentcore_runtime" {
  name = "BedrockAgentCoreRuntimePolicy"
  role = aws_iam_role.agentcore_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRImageAccess"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [
          "arn:aws:ecr:${local.region_account}:repository/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams",
          "logs:CreateLogGroup"
        ]
        Resource = [
          "arn:aws:logs:${local.region_account}:log-group:/aws/bedrock-agentcore/runtimes/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups"
        ]
        Resource = [
          "arn:aws:logs:${local.region_account}:log-group:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${local.region_account}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*"
        ]
      },
      {
        Sid    = "ECRTokenAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Resource = "*"
        Action   = "cloudwatch:PutMetricData"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "bedrock-agentcore"
          }
        }
      },
      {
        Sid    = "GetAgentAccessToken"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetWorkloadAccessToken",
          "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
          "bedrock-agentcore:GetWorkloadAccessTokenForUserId"
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${local.region_account}:workload-identity-directory/default",
          "arn:aws:bedrock-agentcore:${local.region_account}:workload-identity-directory/default/workload-identity/*"
        ]
      },
      {
        Sid    = "BedrockModelInvocation"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:${local.region_account}:*"
        ]
      },
      {
        Sid    = "CreateMemory"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateMemory",
          "bedrock-agentcore:CreateEvent",
          "bedrock-agentcore:ListMemories",
          "bedrock-agentcore:ListEvents",
          "bedrock-agentcore:DeleteMemory"
        ]
        Resource = aws_bedrockagentcore_memory.main.arn,
      },
      {
        Sid    = "RetrieveKB"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve"
        ]
        Resource = ["arn:aws:bedrock:${local.region_account}:knowledge-base/*"]
      }
    ]
  })
}
