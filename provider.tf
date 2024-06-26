terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "eu-west-1"
  profile = "fargateTerraformBlog"
  default_tags {
    tags = {
      repository = "fargate-terraform-blog-infra"
    }
  }
}