variable "oidc_url" {
  type = string
}
variable "oidc_arn" {
  type = string
}
variable "name" {
  type = string
}
variable "namespace" {
  type = string
}
variable "serviceaccount" {
  type = string
}
variable "policy_arns" {
  type = list(string)
}
variable "tags" {
  type = map(string)
  default = {}
}
variable "cluster_name" {
  type = string
}
variable "sa_wildcard" {
  type = bool
  default = false
}
variable "allow_self_assume_role" {
  description = "Determines whether to allow the role to be [assume itself](https://aws.amazon.com/blogs/security/announcing-an-update-to-iam-role-trust-policy-behavior/)"
  type        = bool
  default     = false
}