# ai-agent-accelerator

Get up and running quickly with an AI agent application on AWS on Bedrock AgentCore.

A sample reference implementation that showcases how to quickly build an AI agent using the AWS AgentCore service building blocks. The implementation is fully serverless leveraging AgentCore Memory and Amazon S3 Vectors for Agentic RAG, which means there are no databases to manager or think about.

The agent is built using the [Strands Agent](https://strandsagents.com) Python library and hosted on the [AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agents-tools-runtime.html). The agent has a `retrieve` tool can do semantic search using [Bedrock Knowledge Bases](https://aws.amazon.com/bedrock/knowledge-bases/) which ingests documents from an [S3 bucket](https://aws.amazon.com/s3/) and stores the indexed vectors in [S3 Vectors](https://aws.amazon.com/s3/features/vectors/). User conversation state and history is fully managed by [AgentCore Memory](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory-getting-started.html). Users interact with the agent via a web app (which exposes both a web GUI as well as an HTTP JSON API) and is hosted as a container running on [ECS Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html) fronted with an [ALB](https://aws.amazon.com/elasticloadbalancing/application-load-balancer/). The web app is built using [Python Flask](https://flask.palletsprojects.com) and [HTMX](https://htmx.org/).

![ui](./ui.png)

## Architecture

![architecture](./architecture.png)

This implementation is an evolution of the [AI Chat Accelerator implementation](https://github.com/aws-samples/ai-chat-accelerator) which implemented traditional RAG.

## Key Features

- Rich chatbot GUI running on ECS Fargate
- AI Agent leverages Bedrock AgentCore services
- Implements Agentic RAG with Bedrock Knowledge Bases and S3 Vectors
- Easily add additional tools for the agent to use
- See conversation history and select to see past converations
- Built-in auto scaling architecture (see docs below)
- End to end observability with AgentCore GenAI observability and OpenTelemetry (OTEL)
- Deployable in under 15 minutes (instructions below)

## Usage

Follow the 5 step process below for deploying this solution into your AWS account.

1. Setup/Install prerequisites
2. Deploy stack to AWS using Terraform
3. Upload your documents to the generated S3 bucket
4. Trigger the Bedrock Knowledge Base sync
5. Chat with the AI Agent to access the knowledge in your documents.

### 1. Setup/Install prerequisites

- [Enable the Bedrock models you are using for both the KB ingestion and app generation](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) - ensure you have the latest version as this is using preview APIs
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [jq CLI](https://jqlang.github.io/jq/download/)


### 2. Deploy cloud infrastructure

Export required environment variables.

```sh
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export BUCKET=tf-state-${ACCOUNT}
```

Optionally, create an s3 bucket to store terraform state (this is recommended since the initial db password will be stored in the state). If you already have an s3 bucket, you can update the `BUCKET` variable with the name of your bucket (e.g., `export BUCKET=my-s3-bucket`).

```sh
aws s3 mb s3://${BUCKET}
```

Define your app name (noteL avoid `_`s and `-`s, as AgentCore does not allow dashes for some reason `-`):

```sh
export APP_NAME=agent
```

Set template input parameters, like app `name` in `terraform.tfvars`.

```sh
cd iac
cat << EOF > terraform.tfvars
name = "${APP_NAME}"
tags = {
  app      = "${APP_NAME}"
  template = "https://github.com/aws-samples/sample-ai-agent-accelerator"
}
EOF
```

Deploy using Terraform. Note that Terraform will build both the web app and agent container images and deploy them to AWS.

```sh
terraform init -backend-config="bucket=${BUCKET}" -backend-config="key=${APP_NAME}.tfstate"
terraform apply
```

### 3. Upload your documents to the generated S3 bucket

```sh
cd iac
export DOCS_BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 cp /path/to/docs/ s3://${DOCS_BUCKET}/ --recursive
```

### 4. Call the Bedrock Knowledge Base Sync API

```sh
cd iac
make sync
```

Note that this script calls the `bedrock-agent start-ingestion-job` API. This job will need to successfully complete before the agent will be able to answer questions about your documents.

### 5. Start chatting with your documents in the app

```sh
open $(terraform output -raw endpoint)
```

## Scaling

This architecture can be scaled using two primary levers:

1. ECS horizontal scaling
2. ECS vertical scaling
3. Bedrock scaling

### ECS horizontal scaling

The preferred method of scaling is horizontal autoscaling. Autoscaling is enabled by default and set to scale from 1 to 10 replicas based on an average service CPU and memory utilization of 75%. See the [Terraform module autoscaling input parameters](https://registry.terraform.io/modules/terraform-aws-modules/ecs/aws/latest/submodules/service?tab=inputs) to fine tune this.

### ECS vertical scaling

The size of the individual fargate tasks can be scaled up using the [cpu and memory parameters](./iac/ecs.tf).

### Bedrock scaling

Bedrock cross-region model inference is recommended for increasing throughput using [inference profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles.html).

## Observability

This accelerator ships with OpenTelemetry auto instrumented code for flask, boto3, and AgentCore via the [aws-opentelemetry-distro](https://pypi.org/project/opentelemetry-distro/) library. It will create traces that are available in CloudWatch GenAI Observability. These traces can be useful for understanding how the AI agent is running in production. You can see how an HTTP request is broken down in terms of how much time is spent on various external calls all the way through Bedrock AgentCore Runtime through the Strands framework, to LLM calls.

![Tracing](./tracing.png)

### Disabling tracing

If you'd like to disable the tracing to AWS X-Ray, you can remove the otel sidecar container and dependencies from the ECS task definition as show below.

```
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
```


## Development

```
 Choose a make command to run

  init           run this once to initialize a new python project
  install        install project dependencies
  start          run local project
  baseimage      build base image
  deploy         build and deploy container
  up             run the app locally using docker compose
  down           stop the app
  start-docker   run local project using docker compose
```

### Running locally

In order to run the app locally, create a local file named `.env` with the following variables. The variable, `KNOWLEDGE_BASE_ID` comes from the Terraform output (`cd iac && terraform output`). The others are exported above duing deployment and can be copied here.

```sh
KNOWLEDGE_BASE_ID=xyz
AGENT_RUNTIME=xyz
MEMORY_ID=xyz
```

After setting up your `.env` file, you can run the app locally in docker to iterate on code changes before deploying to AWS. When running the app locally it uses the remote Amazon Bedrock Knowledge Base API. Ensure that you have valid AWS credentials. Running the `make up` command will start an OTEL collector and a web server container.

```sh
make up
```

To stop the environment simply run:

```sh
make down
```
