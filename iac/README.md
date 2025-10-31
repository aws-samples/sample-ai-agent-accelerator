# IaC

This repo uses [asdf](https://asdf-vm.com/) to manage the `terraform` CLI and the various other tools it depends upon.

![architecture](./architecture.png)


```
 Choose a make command to run

  init    project initialization - install tools and register git hook
```

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.18.0 |
| <a name="requirement_awscc"></a> [awscc](#requirement\_awscc) | ~> 1.0 |
| <a name="requirement_docker"></a> [docker](#requirement\_docker) | ~> 3.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.18.0 |
| <a name="provider_docker"></a> [docker](#provider\_docker) | ~> 3.0 |
| <a name="provider_local"></a> [local](#provider\_local) | ~> 2.0 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_alb"></a> [alb](#module\_alb) | terraform-aws-modules/alb/aws | ~> 9.0 |
| <a name="module_ecs_cluster"></a> [ecs\_cluster](#module\_ecs\_cluster) | terraform-aws-modules/ecs/aws//modules/cluster | ~> 6.0 |
| <a name="module_ecs_service"></a> [ecs\_service](#module\_ecs\_service) | terraform-aws-modules/ecs/aws//modules/service | ~> 6.0 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 6.0 |

## Resources

| Name | Type |
|------|------|
| [aws_bedrockagentcore_agent_runtime.main](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/bedrockagentcore_agent_runtime) | resource |
| [aws_bedrockagentcore_memory.main](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/bedrockagentcore_memory) | resource |
| [aws_ecr_repository.agent](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository.web](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/ecr_repository) | resource |
| [aws_iam_role.agentcore_runtime](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/iam_role) | resource |
| [aws_iam_role.bedrock_kb_role](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.agentcore_runtime](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.kb](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.llm_logs](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.main](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.main](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_security_group.ecs_service](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/resources/security_group) | resource |
| [docker_image.agent](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image) | resource |
| [docker_image.web](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image) | resource |
| [docker_registry_image.agent](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/registry_image) | resource |
| [docker_registry_image.web](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/registry_image) | resource |
| [null_resource.bedrock_data_source](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.bedrock_knowledge_base](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/data-sources/caller_identity) | data source |
| [aws_ecr_authorization_token.token](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/data-sources/ecr_authorization_token) | data source |
| [aws_iam_policy_document.kb](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kb_assume](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/6.18.0/docs/data-sources/region) | data source |
| [local_file.ds_id](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |
| [local_file.kb_id](https://registry.terraform.io/providers/hashicorp/local/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_container_name"></a> [container\_name](#input\_container\_name) | The name of the container | `string` | `"app"` | no |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | The port that the container is listening on | `number` | `8080` | no |
| <a name="input_health_check"></a> [health\_check](#input\_health\_check) | A map containing configuration for the health check | `string` | `"/health"` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of this template (e.g., my-app-prod) | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The AWS region to deploy to (e.g., us-east-1) | `string` | `"us-east-1"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_agentcore_ecr_repository_url"></a> [agentcore\_ecr\_repository\_url](#output\_agentcore\_ecr\_repository\_url) | The URL of the AgentCore ECR repository |
| <a name="output_agentcore_memory_id"></a> [agentcore\_memory\_id](#output\_agentcore\_memory\_id) | The ID of the AgentCore memory |
| <a name="output_agentcore_runtime_arn"></a> [agentcore\_runtime\_arn](#output\_agentcore\_runtime\_arn) | The ARN of the AgentCore runtime |
| <a name="output_bedrock_knowledge_base_data_source_id"></a> [bedrock\_knowledge\_base\_data\_source\_id](#output\_bedrock\_knowledge\_base\_data\_source\_id) | the id of the created bedrock knowledge base data source |
| <a name="output_bedrock_knowledge_base_id"></a> [bedrock\_knowledge\_base\_id](#output\_bedrock\_knowledge\_base\_id) | the id of the created bedrock knowledge base |
| <a name="output_ecs_cluster_arn"></a> [ecs\_cluster\_arn](#output\_ecs\_cluster\_arn) | The arn of the ecs cluster that was created or referenced |
| <a name="output_ecs_cluster_name"></a> [ecs\_cluster\_name](#output\_ecs\_cluster\_name) | The name of the ecs cluster that was created or referenced |
| <a name="output_ecs_service_name"></a> [ecs\_service\_name](#output\_ecs\_service\_name) | The arn of the fargate ecs service that was created |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | The web application endpoint |
| <a name="output_lb_arn"></a> [lb\_arn](#output\_lb\_arn) | The arn of the load balancer |
| <a name="output_lb_dns"></a> [lb\_dns](#output\_lb\_dns) | The load balancer DNS name |
| <a name="output_name"></a> [name](#output\_name) | The name of the application |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | The name of the s3 bucket that was created |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the VPC |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
