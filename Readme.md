# Crossform: Cloud Infrastructure Management Tool

Crossform combines the GitOps methodology with cloud services, offering a convenient syntax for infrastructure management.


The main disadvantage of ArgoCD is the one-way data flow. 
If we have created a resource, we cannot get the attributes of this resource, for example ARN, which makes working with cloud resources from Kubernetes extremely inconvenient.
Crossplane tried to solve this problem. But their description language is simply monstrous, it is very inconvenient. 
Terraform has a good language but is not very compatible with ArgoCD and GitOps methodology. 
This tool allows you to integrate GitOps methodology and clouds and has a very convenient language syntax.

## Issues with Existing Solutions

- **ArgoCD**: One-way data flow makes it difficult to retrieve attributes of created resources, such as ARNs, complicating work with cloud resources from Kubernetes.
- **Crossplane**: Complex and cumbersome resource description language.
- **Terraform**: Although Terraform supports GitOps approaches through integration with ArgoCD, managing state and secrets may require additional configuration, complicating automation processes.

## Advantages of Crossform

- Deep integration of the GitOps methodology with cloud services.
- Simple and intuitive syntax for describing infrastructure.

## Project Structure

The project is organized into modules and libraries, providing flexibility and code reuse:

- **Modules**: Located in the `examples/modules` directory, containing components for managing various resources like VPC, EKS, and ALB.
- **Libraries**: Found in `examples/libs`, providing helper functions for working with infrastructure components.

## Usage Examples

The [example](https://github.com/zefir01/crossform/tree/main/examples) directory contains configuration samples demonstrating how to use Crossform for cloud infrastructure management. For instance, the file `examples/test2/main.jsonnet` shows how to use VPC and EKS modules to deploy a Kubernetes cluster.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/zefir01/crossform.git
