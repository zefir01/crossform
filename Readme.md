# Crossform, cloud infrastructure management tool

The main disadvantage of ArgoCD is the one-way data flow. 
If we have created a resource, we cannot get the attributes of this resource, for example ARN, which makes working with cloud resources from Kubernetes extremely inconvenient.
Crossplane tried to solve this problem. But their description language is simply monstrous, it is very inconvenient. 
Terraform has a good language but is not very compatible with ArgoCD and GitOps methodology. 
This tool allows you to integrate GitOps methodology and clouds and has a very convenient language syntax.

One [example](https://github.com/zefir01/crossform/tree/main/examples) is worth a thousand descriptions

If it's not obvious how to use this, look at the second [example](https://github.com/zefir01/crossform/tree/main/tower)