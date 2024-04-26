variable "domain" {
  type = string
}
variable "region" {
  type = string
}
variable "cluster_name" {
  type = string
}
variable "argo_repo" {
  type = string
}
variable "oidc" {
  type = list(object({
    type              = string
    name              = string
    hostName          = string
    client_id         = string
    client_secret_key = string
    org               = string
    team              = string
    role              = string
  }))
  default = []
}


variable "oidc_url" {
  type = string
}
variable "oidc_arn" {
  type = string
}
variable "argo_branch" {
  type = string
}
variable "knownHosts" {
  type = list(string)
  default = []
}
variable "argo_ssh_key" {
  type = string
}