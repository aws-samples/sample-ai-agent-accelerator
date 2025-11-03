locals {
  embedding_model_arn = "arn:aws:bedrock:${local.region}::foundation-model/amazon.titan-embed-text-v2:0"
  knowledge_base_id   = data.external.kb_info.result.kb_id
  knowledge_base_arn  = data.external.kb_info.result.kb_arn
  data_source_id      = data.external.ds_info.result.ds_id
}

# WORKAROUND: Using terraform_data with AWS CLI for S3 vectors knowledge base creation
#
# Amazon S3 Vectors is currently in preview and does not have Terraform support.
# The native aws_bedrockagent_knowledge_base resource only supports traditional vector stores:
# - OpenSearch Serverless, Pinecone, Redis Enterprise Cloud, Amazon RDS
#
# S3 vectors support is tracked in GitHub issues:
# - https://github.com/hashicorp/terraform-provider-aws/issues/43409
# - https://github.com/hashicorp/terraform-provider-aws/issues/43438
#
# TODO: Replace with native resource when S3 vectors support is added to Terraform provider
resource "terraform_data" "bedrock_knowledge_base" {
  depends_on = [aws_iam_role_policy.kb]

  triggers_replace = {
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
      aws s3vectors create-vector-bucket --vector-bucket-name "$VECTOR_BUCKET_NAME" || echo "Vector bucket may already exist"

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
        --metadata-configuration '{"nonFilterableMetadataKeys":["AMAZON_BEDROCK_TEXT","AMAZON_BEDROCK_METADATA"]}' || echo "Index may already exist"

      # Get vector index ARN
      S3_INDEX_ARN=$(aws s3vectors get-index \
        --vector-bucket-name "$VECTOR_BUCKET_NAME" \
        --index-name "$S3_INDEX_NAME" \
        --query 'index.indexArn' \
        --output text)

      # Create knowledge base with retry
      echo "Creating Bedrock knowledge base..."
      i=1
      while [ $i -le 3 ]; do
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
          }'); then

          echo "Knowledge base created successfully"
          break
        elif [ $i -eq 3 ]; then
          echo "Failed to create knowledge base after 3 attempts"
          exit 1
        else
          echo "Attempt $i failed, retrying in 15 seconds..."
          sleep 15
        fi
        i=$((i + 1))
      done
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e

      # Always try to delete S3 vector resources first (they're predictably named)
      VECTOR_BUCKET_NAME="${self.triggers_replace.name}-vectors"
      S3_INDEX_NAME="${self.triggers_replace.name}-index"

      echo "Cleaning up S3 vectors resources..."
      aws s3vectors delete-index \
        --vector-bucket-name "$VECTOR_BUCKET_NAME" \
        --index-name "$S3_INDEX_NAME" || echo "Index may not exist"

      aws s3vectors delete-vector-bucket \
        --vector-bucket-name "$VECTOR_BUCKET_NAME" || echo "Vector bucket may not exist"

      # Try to get KB ID from AWS and delete if found
      KB_ID=$(aws bedrock-agent list-knowledge-bases \
        --query "knowledgeBaseSummaries[?name=='${self.triggers_replace.name}'].knowledgeBaseId" \
        --output text 2>/dev/null || echo "")

      if [ -n "$KB_ID" ] && [ "$KB_ID" != "None" ]; then
        echo "Deleting knowledge base: $KB_ID"
        aws bedrock-agent delete-knowledge-base --knowledge-base-id "$KB_ID" || echo "KB may not exist"
      else
        echo "No knowledge base found to delete"
      fi
    EOT
  }
}

# Extract KB info using external data source
data "external" "kb_info" {
  depends_on = [terraform_data.bedrock_knowledge_base]

  program = ["bash", "-c", <<-EOT
    KB_ID=$(aws bedrock-agent list-knowledge-bases \
      --query "knowledgeBaseSummaries[?name=='${var.name}'].knowledgeBaseId" \
      --output text)
    KB_ARN=$(aws bedrock-agent list-knowledge-bases \
      --query "knowledgeBaseSummaries[?name=='${var.name}'].knowledgeBaseArn" \
      --output text)

    if [ -n "$KB_ID" ] && [ "$KB_ID" != "None" ]; then
      echo "{\"kb_id\":\"$KB_ID\",\"kb_arn\":\"$KB_ARN\"}"
    else
      echo "{\"kb_id\":\"\",\"kb_arn\":\"\"}"
    fi
  EOT
  ]
}

# WORKAROUND: Using terraform_data with AWS CLI instead of aws_bedrockagent_data_source
#
# The native Terraform resource aws_bedrockagent_data_source fails with:
# "AccessDeniedException: User is not authorized to perform: bedrock:CreateDataSource"
# even when the user has AdministratorAccess permissions.
#
# This is a known issue with the Terraform AWS provider v6.18.0 where the provider
# incorrectly handles permissions for Bedrock Agent data source creation.
# The AWS CLI works correctly with the same credentials.
#
# TODO: Replace with native resource when provider bug is fixed
resource "terraform_data" "bedrock_data_source" {
  depends_on = [terraform_data.bedrock_knowledge_base]

  triggers_replace = {
    knowledge_base_id = local.knowledge_base_id
    bucket_arn        = aws_s3_bucket.main.arn
    bucket_name       = aws_s3_bucket.main.bucket
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Wait for KB to be ready and create data source with retry
      echo "Creating Bedrock knowledge base data source..."
      i=1
      while [ $i -le 5 ]; do
        if DS_JSON=$(aws bedrock-agent create-data-source \
          --knowledge-base-id "${local.knowledge_base_id}" \
          --name "${aws_s3_bucket.main.bucket}" \
          --data-source-configuration '{
            "type": "S3",
            "s3Configuration": {
              "bucketArn": "${aws_s3_bucket.main.arn}"
            }
          }' \
          --data-deletion-policy "RETAIN" 2>/dev/null); then

          echo "Data source created successfully"
          break
        elif [ $i -eq 5 ]; then
          echo "Failed to create data source after 5 attempts"
          exit 1
        else
          echo "Attempt $i failed, retrying in 10 seconds..."
          sleep 10
        fi
        i=$((i + 1))
      done
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e

      # Try to get data source ID from AWS
      DS_ID=$(aws bedrock-agent list-data-sources \
        --knowledge-base-id "${self.triggers_replace.knowledge_base_id}" \
        --query "dataSourceSummaries[?name=='${self.triggers_replace.bucket_name}'].dataSourceId" \
        --output text 2>/dev/null || echo "")

      if [[ -n "$DS_ID" && "$DS_ID" != "None" ]]; then
        # Delete data source
        aws bedrock-agent delete-data-source \
          --knowledge-base-id "${self.triggers_replace.knowledge_base_id}" \
          --data-source-id "$DS_ID" || true
      fi
    EOT
  }
}

# Extract data source info using external data source
data "external" "ds_info" {
  depends_on = [terraform_data.bedrock_data_source]

  program = ["bash", "-c", <<-EOT
    DS_ID=$(aws bedrock-agent list-data-sources \
      --knowledge-base-id "${local.knowledge_base_id}" \
      --query "dataSourceSummaries[?name=='${aws_s3_bucket.main.bucket}'].dataSourceId" \
      --output text)

    if [ -n "$DS_ID" ] && [ "$DS_ID" != "None" ]; then
      echo "{\"ds_id\":\"$DS_ID\"}"
    else
      echo "{\"ds_id\":\"\"}"
    fi
  EOT
  ]
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
