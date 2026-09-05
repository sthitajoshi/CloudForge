terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "cloudforge-tf-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudforge-tf-lock"

    # LocalStack backend config — see terraform/envs/dev/backend.hcl note.
    # Required because LocalStack isn't real AWS: skip validation/creds
    # checks and point every call at the local endpoint.
    endpoints = {
      s3       = "http://localhost:4566"
      dynamodb = "http://localhost:4566"
    }
    access_key                  = "test"
    secret_key                  = "test"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3       = "http://localhost:4566"
    iam      = "http://localhost:4566"
    sts      = "http://localhost:4566"
    ec2      = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
  }
}

module "vpc" {
  source               = "../../modules/vpc"
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "app_bucket" {
  source      = "../../modules/app_bucket"
  env         = var.env
  bucket_name = "cloudforge-${var.env}-app"
}

module "iam" {
  source          = "../../modules/iam"
  env             = var.env
  app_bucket_name = module.app_bucket.bucket_name
}
