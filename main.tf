terraform {
  required_version = "~>0.12.0"
}

provider "aws" {
  version = "~> 2.44"
  region   = var.region
}

module "vpc" {
  source             = "./vpc"
  name               = var.name
  environment        = var.environment
  cidr               = var.cidr
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
  availability_zones = var.availability_zones
}

module "security_groups" {
  source      = "./security-groups"
  name        = var.name
  environment = var.environment
  vpc_id      = module.vpc.id
}

module "eks" {
  source                  = "./eks"
  name                    = var.name
  environment             = var.environment
  region                  = var.region
  vpc_id                  = module.vpc.id
  private_subnets         = module.vpc.private_subnets
  public_subnets          = module.vpc.public_subnets
  cluster_security_groups = [module.security_groups.default.id]
  kubeconfig_path         = var.kubeconfig_path
}
