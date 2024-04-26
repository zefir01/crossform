data "aws_availability_zones" "available" {
}

locals {
  cidr    = "10.0.0.0/16"
  subnets = cidrsubnets(local.cidr, 2, 2, 5, 5)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name                 = "crossform-tower"
  cidr                 = local.cidr
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = [local.subnets[0], local.subnets[1]]
  public_subnets       = [local.subnets[2], local.subnets[3]]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_classiclink   = null

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = "1"
  }
}