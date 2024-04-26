terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    helm       = {}
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

#provider "kubectl" {
#  host                   = module.eks.cluster_endpoint
#  cluster_ca_certificate = module.eks.cluster_certificate_authority_data
#  load_config_file       = false
#  exec {
#    api_version = "client.authentication.k8s.io/v1beta1"
#    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
#    command     = "aws"
#  }
#}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}