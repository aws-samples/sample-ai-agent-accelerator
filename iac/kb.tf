locals {
  embedding_model_arn = "arn:aws:bedrock:${local.region}::foundation-model/amazon.titan-embed-text-v2:0"
}

# Create knowledge base using local-exec with output capture
# WORKAROUND: Using null_resource with AWS CLI for S3 vectors knowledge base creation
#
# Amazon S3 Vectors is currently in preview and does not have Terraform support.
# The native aws_bedrockagent_knowledge_base resource only supports traditional vector stores:
# - OpenSearch Serverless
# - Pinecone
# - Redis Enterprise Cloud
# - Amazon RDS
#
# S3 vectors support is tracked in GitHub issues:
# - https://github.com/hashicorp/terraform-provider-aws/issues/43409
# - https://github.com/hashicorp/terraform-provider-aws/issues/43438
#
# TODO: Replace with native resource when S3 vectors support is added to Terraform provider
resource "null_resource" "bedrock_knowledge_base" {
  depends_on = [aws_iam_role_policy.kb]

  triggers = {
    region          = local.region
    name            = var.name
    description     = "kb for ${var.name}"
    kb_role_arn     = aws_iam_role.bedrock_kb_role.arn
    embedding_model = local.embedding_model_arn
    bucket_name     = aws_s3_bucket.main.bucket
    bucket_arn      = aws_s3_bucket.main.arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Create S3 vector bucket
      echo "Creating S3 vector bucket..."
      VECTOR_BUCKET_NAME="${var.name}-vectors"
      aws s3vectors create-vector-bucket --vector-bucket-name "$VECTOR_BUCKET_NAME"

      # Get vector bucket ARN
      VECTOR_BUCKET_ARN=$(aws s3vectors get-vector-bucket \
        --vector-bucket-name "$VECTOR_BUCKET_NAME" \
        --query 'vectorBucket.vectorBucketArn' \
        --output text)

      # Create S3 vector index
      echo "Creating S3 vector index..."
      S3_INDEX_NAME="${var.name}-index"
      aws s3vectors create-index \
        --vector-bucket-name "$VECTOR_BUCKET_NAME" \
        --index-name "$S3_INDEX_NAME" \
        --data-type "float32" \
        --dimension 1024 \
        --distance-metric "cosine" \
        --metadata-configuration '{"nonFilterableMetadataKeys":["AMAZON_BEDROCK_TEXT","AMAZON_BEDROCK_METADATA"]}'

      # Get vector index ARN
      S3_INDEX_ARN=$(aws s3vectors get-index \
        --vector-bucket-name "$VECTOR_BUCKET_NAME" \
        --index-name "$S3_INDEX_NAME" \
        --query 'index.indexArn' \
        --output text)

      # Create knowledge base with retry
      echo "Creating Bedrock knowledge base..."
      for i in {1..3}; do
        if KB_JSON=$(aws bedrock-agent create-knowledge-base \
          --name "${var.name}" \
          --description "kb for ${var.name}" \
          --role-arn "${aws_iam_role.bedrock_kb_role.arn}" \
          --knowledge-base-configuration '{
            "type": "VECTOR",
            "vectorKnowledgeBaseConfiguration": {
              "embeddingModelArn": "${local.embedding_model_arn}"
            }
          }' \
          --storage-configuration '{
            "type": "S3_VECTORS",
            "s3VectorsConfiguration": {
              "indexArn": "'$S3_INDEX_ARN'",
              "vectorBucketArn": "'$VECTOR_BUCKET_ARN'"
            }
          }' 2>/dev/null); then

          # Extract and save KB info
          echo "$KB_JSON" | jq -r '.knowledgeBase.knowledgeBaseId' > kb_id.txt
          echo "$KB_JSON" | jq -r '.knowledgeBase.knowledgeBaseArn' > kb_arn.txt
          echo "Knowledge base created successfully"
          break
        elif [[ $i -eq 3 ]]; then
          echo "Failed to create knowledge base after 3 attempts"
          exit 1
        else
          echo "Attempt $i failed, retrying in 15 seconds..."
          sleep 15
        fi
      done
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e

      # Read KB ID if file exists
      if [[ -f kb_id.txt ]]; then
        KB_ID=$(cat kb_id.txt)

        # Delete knowledge base
        aws bedrock-agent delete-knowledge-base --knowledge-base-id "$KB_ID" || true

        # Delete S3 vector resources
        VECTOR_BUCKET_NAME="${self.triggers.name}-vectors"
        S3_INDEX_NAME="${self.triggers.name}-index"

        aws s3vectors delete-index \
          --vector-bucket-name "$VECTOR_BUCKET_NAME" \
          --index-name "$S3_INDEX_NAME" || true

        aws s3vectors delete-vector-bucket \
          --vector-bucket-name "$VECTOR_BUCKET_NAME" || true

        # Clean up files
        rm -f kb_id.txt kb_arn.txt
      fi
    EOT
  }
}

# Read KB info from files created by provisioner
data "local_file" "kb_id" {
  depends_on = [null_resource.bedrock_knowledge_base]
  filename   = "${path.module}/kb_id.txt"
}

locals {
  knowledge_base_id = trimspace(try(data.local_file.kb_id.content, ""))
}

# WORKAROUND: Using null_resource with AWS CLI instead of aws_bedrockagent_data_source
#
# The native Terraform resource aws_bedrockagent_data_source fails with:
# "AccessDeniedException: User is not authorized to perform: bedrock:CreateDataSource"
# even when the user has AdministratorAccess permissions.
#
# This is a known issue with the Terraform AWS provider v6.18.0 where the provider
# incorrectly handles permissions for Bedrock Agent data source creation.
# The AWS CLI works correctly with the same credentials.
#
# TODO: Replace with native resource when provider bug is fixed:
# resource "aws_bedrockagent_data_source" "main" {
#   knowledge_base_id = local.knowledge_base_id
#   name              = aws_s3_bucket.main.bucket
#   data_source_configuration {
#     type = "S3"
#     s3_configuration {
#       bucket_arn = aws_s3_bucket.main.arn
#     }
#   }
#   data_deletion_policy = "RETAIN"
#   depends_on = [null_resource.bedrock_knowledge_base]
# }
resource "null_resource" "bedrock_data_source" {
  triggers = {
    knowledge_base_id = trimspace(local.knowledge_base_id)
    bucket_arn        = aws_s3_bucket.main.arn
    bucket_name       = aws_s3_bucket.main.bucket
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Create data source
      echo "Creating Bedrock knowledge base data source..."
      DS_JSON=$(aws bedrock-agent create-data-source \
        --knowledge-base-id "${trimspace(self.triggers.knowledge_base_id)}" \
        --name "${self.triggers.bucket_name}" \
        --data-source-configuration '{
          "type": "S3",
          "s3Configuration": {
            "bucketArn": "${self.triggers.bucket_arn}"
          }
        }' \
        --data-deletion-policy "RETAIN" 2>/dev/null)

      # Extract and save data source ID
      echo "$DS_JSON" | jq -r '.dataSource.dataSourceId' > ds_id.txt
      echo "Data source created successfully"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e

      # Read data source ID if file exists
      if [[ -f ds_id.txt ]]; then
        DS_ID=$(cat ds_id.txt)

        # Delete data source
        aws bedrock-agent delete-data-source \
          --knowledge-base-id "${trimspace(self.triggers.knowledge_base_id)}" \
          --data-source-id "$DS_ID" || true

        # Clean up file
        rm -f ds_id.txt
      fi
    EOT
  }

  depends_on = [null_resource.bedrock_knowledge_base]
}

# Data source to read the created data source ID
data "local_file" "ds_id" {
  filename   = "ds_id.txt"
  depends_on = [null_resource.bedrock_data_source]
}

locals {
  data_source_id = trimspace(try(data.local_file.ds_id.content, ""))
}

resource "aws_iam_role" "bedrock_kb_role" {
  name               = "BedrockExecutionRoleForKnowledgeBase-${var.name}"
  assume_role_policy = data.aws_iam_policy_document.kb_assume.json
}

resource "aws_iam_role_policy" "kb" {
  role   = aws_iam_role.bedrock_kb_role.name
  policy = data.aws_iam_policy_document.kb.json
}

data "aws_iam_policy_document" "kb_assume" {
  statement {
    sid     = "AmazonBedrockKnowledgeBaseTrustPolicy"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${local.region_account}:knowledge-base/*"]
    }
  }
}

data "aws_iam_policy_document" "kb" {
  statement {
    sid       = "BedrockInvokeModelStatement"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.embedding_model_arn]
  }

  statement {
    sid       = "S3ListBucketStatement"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.main.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "S3GetObjectStatement"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "S3VectorsStatement"
    effect = "Allow"
    actions = [
      "s3vectors:QueryVectors",
      "s3vectors:PutVectors",
      "s3vectors:DeleteVectors",
      "s3vectors:GetVectors",
      "s3vectors:ListVectors",
      "s3vectors:GetIndex",
      "s3vectors:ListIndexes",
      "s3vectors:GetVectorBucket",
      "s3vectors:ListVectorBuckets"
    ]
    resources = [
      "arn:aws:s3vectors:${local.region_account}:bucket/${var.name}-vectors",
      "arn:aws:s3vectors:${local.region_account}:bucket/${var.name}-vectors/*"
    ]
  }
}
