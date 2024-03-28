# Terraform project used for the Fargate Terraform blog

This is an example repository to make an ECS fargate setup with terraform. In this blog you will see the prefix 'ftb' meaning: Fargate Terraform Blog.
## Prerequisites
* This project assumes you have valid AWS credentials in your environment variables or [/.aws/credentials]((https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)) file.
* [Terraform CLI](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
## Config
The project relies on a few external parameters. These variables need to be entered when deploying the infrastructure.

| Parameter name   | Default value | Description                                                                                                                    |
|------------------|---------------|--------------------------------------------------------------------------------------------------------------------------------|
| vpc_id           | NA            | ID of the VPC our stack will be deployed in                                                                                    |
| subnet_ids       | NA            | Comma seperated list of subnet IDs our infrastructure will be deployed in for multi-AZ                                         |
| routing_table_id | NA            | ID if the main routing table that will be associated with the S3 GW VPC-Endpoint                                               |

## Running terraform
You can run the current terraform config with 
```terraform apply```

## Destroying terraform
You can undo the terraform apply with
```terraform destroy```
