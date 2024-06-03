terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    bcrypt = {
      source  = "viktorradnai/bcrypt"
      version = "0.1.2"
    }
    github = {
      source = "integrations/github"
    }
  }
}

resource "kubernetes_namespace" "argo" {
  metadata {
    name = "argo"
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "random_password" "password" {
  length  = 16
  special = false
}

resource "bcrypt_hash" "argo_pass" {
  cleartext = random_password.password.result
}

data "aws_iam_policy_document" "assume" {
  statement {
    sid       = "AssumeRole"
    actions   = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity"]
    resources = ["*"]
  }
}
resource "aws_iam_policy" "argo" {
  name   = "argocd-assume"
  path   = "/"
  policy = data.aws_iam_policy_document.assume.json
}


module "irsa_argo" {
  source                 = "../irsa"
  name                   = "argo"
  cluster_name           = var.cluster_name
  namespace              = "argo"
  serviceaccount         = "argocd-*"
  sa_wildcard            = true
  oidc_url               = var.oidc_url
  oidc_arn               = var.oidc_arn
  policy_arns            = [aws_iam_policy.argo.arn]
  allow_self_assume_role = true
}

resource "helm_release" "argo-cd" {
  depends_on       = [kubernetes_config_map.argo_ssh, kubernetes_secret_v1.argo_wf_sso_secret]
  name             = "argo-cd"
  chart            = "argo-cd"
  version          = "6.4.1"
  repository       = "https://argoproj.github.io/argo-helm"
  namespace        = "argo"
  create_namespace = false
  cleanup_on_fail  = true


  #  lifecycle {
  #    ignore_changes = [set]
  #  }

  values = [
    <<EOF
global:
  logging:
    level: debug
  securityContext:
    fsGroup: 999
repoServer:
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
  volumes:
    - name: config-volume
      configMap:
        name: repo-server-ssh-cm
  volumeMounts:
    - name: config-volume
      mountPath: /home/argocd/.ssh/config
      subPath: ssh_config
applicationSet:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: ${module.irsa_argo.arn}
  extraVolumes:
    - name: config-volume
      configMap:
        name: repo-server-ssh-cm
  extraVolumeMounts:
    - name: config-volume
      mountPath: /home/argocd/.ssh/config
      subPath: ssh_config
controller:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: ${module.irsa_argo.arn}
  resources:
    limits:
      cpu: 2
      memory: 4Gi
    requests:
      cpu: 250m
      memory: 1Gi
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8082"
    prometheus.io/path: "/metrics"
server:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: ${module.irsa_argo.arn}
  resources:
    limits:
      cpu: 1
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi
  ingress:
    enabled: true
    hostname: argo.${var.domain}
    ingressClassName: alb
    https: false
    tls:
      - hosts:
        - argo.${var.domain}
        secretName: myingress-cert
    annotations:
      alb.ingress.kubernetes.io/load-balancer-attributes: routing.http.drop_invalid_header_fields.enabled=true
      external-dns.kubernetes.io/enable: true
      alb.ingress.kubernetes.io/scheme: internet-facing
      external-dns.kubernetes.io/enable: "true"
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/load-balancer-name: argo
      alb.ingress.kubernetes.io/target-type: ip
%{ if length(var.oidc) >0 }
dex:
  env:
    - name: ARGO_WORKFLOWS_SSO_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: argo-workflows-sso
          key: client-secret
%{ endif }
configs:
  params:
    application.namespaces: "*"
  ssh:
    knownHosts: |
      [ssh.github.com]:443 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
      [ssh.github.com]:443 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      [ssh.github.com]:443 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
      bitbucket.org ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPIQmuzMBuKdWeF4+a2sjSSpBK0iqitSQ+5BM9KhpexuGt20JpTVM7u5BDZngncgrqDMbWdxMWWOGtZ9UgbqgZE=
      bitbucket.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIazEu89wgQZ4bqs3d63QSMzYVa0MuJ2e2gKTKqu+UUO
      bitbucket.org ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDQeJzhupRu0u0cdegZIa8e86EG2qOCsIsD1Xw0xSeiPDlCr7kq97NLmMbpKTX6Esc30NuoqEEHCuc7yWtwp8dI76EEEB1VqY9QJq6vk+aySyboD5QF61I/1WeTwu+deCbgKMGbUijeXhtfbxSxm6JwGrXrhBdofTsbKRUsrN1WoNgUa8uqN1Vx6WAJw1JHPhglEGGHea6QICwJOAr/6mrui/oB7pkaWKHj3z7d1IC4KWLtY47elvjbaTlkN04Kc/5LFEirorGYVbt15kAUlqGM65pk6ZBxtaO3+30LVlORZkxOh+LKL/BvbZ/iRNhItLqNyieoQj/uh/7Iv4uyH/cV/0b4WDSd3DptigWq84lJubb9t/DnZlrJazxyDCulTmKdOR7vs9gMTo+uoIrPSb8ScTtvw65+odKAlBj59dhnVp9zd7QUojOpXlL62Aw56U4oO+FALuevvMjiWeavKhJqlR7i5n9srYcrNV7ttmDw7kf/97P5zauIhxcjX+xHv4M=
      github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
      github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
      gitlab.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=
      gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf
      gitlab.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Yt0aGROY5qX2UKSeOvuP4D6TPqKF1onrSzH9bx9XUf2lEdWT/ia1NEKjunUqu1xOB/StKDHMoX4/OKyIzuS0q/T1zOATthvasJFoPrAjkohTyaDUz2LN5JoH839hViyEG82yB+MjcFV5MU3N1l1QL3cVUCh93xSaua1N85qivl+siMkPGbO5xR/En4iEY6K2XPASUEMaieWVNTRCtJ4S8H+9
      ssh.dev.azure.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7Hr1oTWqNqOlzGJOfGJ4NakVyIzf1rXYd4d7wo6jBlkLvCA4odBlL0mDUyZ0/QUfTTqeu+tm22gOsv+VrVTMk6vwRU75gY/y9ut5Mb3bR5BV58dKXyq9A9UeB5Cakehn5Zgm6x1mKoVyf+FFn26iYqXJRgzIZZcZ5V6hrE0Qg39kZm4az48o0AUbf6Sp4SLdvnuMa2sVNwHBboS7EJkm57XQPVU3/QpyNLHbWDdzwtrlS+ez30S3AdYhLKEOxAG8weOnyrtLJAUen9mTkol8oII1edf7mWWbWVf0nBmly21+nZcmCTISQBtdcyPaEno7fFQMDD26/s0lfKob4Kw8H
      vs-ssh.visualstudio.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7Hr1oTWqNqOlzGJOfGJ4NakVyIzf1rXYd4d7wo6jBlkLvCA4odBlL0mDUyZ0/QUfTTqeu+tm22gOsv+VrVTMk6vwRU75gY/y9ut5Mb3bR5BV58dKXyq9A9UeB5Cakehn5Zgm6x1mKoVyf+FFn26iYqXJRgzIZZcZ5V6hrE0Qg39kZm4az48o0AUbf6Sp4SLdvnuMa2sVNwHBboS7EJkm57XQPVU3/QpyNLHbWDdzwtrlS+ez30S3AdYhLKEOxAG8weOnyrtLJAUen9mTkol8oII1edf7mWWbWVf0nBmly21+nZcmCTISQBtdcyPaEno7fFQMDD26/s0lfKob4Kw8H
%{ for h in var.knownHosts }
      ${h}
%{ endfor }
%{ if length(var.oidc) >0 }
  rbac:
    policy.default: role:readonly
    policy.csv: |
       p, role:org-admin, *, *, */*, allow
%{ for o in var.oidc }
       g, "${o.org}:${o.team}", role:${o.role}
%{ endfor }
%{ endif }
  cm:
    application.resourceTrackingMethod: annotation
%{ if length(var.oidc) >0 }
    url: https://${var.domain}
    dex.config: |
      issuer: https://${var.domain}/api/dex
      logger:
        level: debug
      connectors:
%{ for o in var.oidc }
      - type: ${o.type}
        id: ${o.name}
        name: ${o.name}
        config:
          hostName: "${o.hostName}"
          clientID: "${o.client_id}"
          clientSecret: "${o.client_secret_key}"
          orgs:
            - name: ${o.org}
%{ endfor }
%{ endif }
    resource.exclusions: |
      - apiGroups:
        - "*"
        kinds:
        - ProviderConfigUsage
    resource.customizations: |
      "*.upbound.io/*":
        health.lua: |
          health_status = {
            status = "Progressing",
            message = "Provisioning ..."
          }

          local function contains (table, val)
            for i, v in ipairs(table) do
              if v == val then
                return true
              end
            end
            return false
          end

          local has_no_status = {
            "ProviderConfig",
            "ProviderConfigUsage"
          }

          if obj.status == nil or next(obj.status) == nil and contains(has_no_status, obj.kind) then
            health_status.status = "Healthy"
            health_status.message = "Resource is up-to-date."
            return health_status
          end

          if obj.status == nil or next(obj.status) == nil or obj.status.conditions == nil then
            if obj.kind == "ProviderConfig" and obj.status.users ~= nil then
              health_status.status = "Healthy"
              health_status.message = "Resource is in use."
              return health_status
            end
            return health_status
          end

          for i, condition in ipairs(obj.status.conditions) do
            if condition.type == "LastAsyncOperation" then
              if condition.status == "False" then
                health_status.status = "Degraded"
                health_status.message = condition.message
                return health_status
              end
            end

            if condition.type == "Synced" then
              if condition.status == "False" then
                health_status.status = "Degraded"
                health_status.message = condition.message
                return health_status
              end
            end

            if condition.type == "Ready" then
              if condition.status == "True" then
                health_status.status = "Healthy"
                health_status.message = "Resource is up-to-date."
                return health_status
              end
            end
          end

          return health_status

      "*.crossplane.io/*":
        health.lua: |
          health_status = {
            status = "Progressing",
            message = "Provisioning ..."
          }

          local function contains (table, val)
            for i, v in ipairs(table) do
              if v == val then
                return true
              end
            end
            return false
          end

          local has_no_status = {
            "Composition",
            "CompositionRevision",
            "DeploymentRuntimeConfig",
            "ControllerConfig",
            "ProviderConfig",
            "ProviderConfigUsage"
          }
          if obj.status == nil or next(obj.status) == nil and contains(has_no_status, obj.kind) then
              health_status.status = "Healthy"
              health_status.message = "Resource is up-to-date."
            return health_status
          end

          if obj.status == nil or next(obj.status) == nil or obj.status.conditions == nil then
            if obj.kind == "ProviderConfig" and obj.status.users ~= nil then
              health_status.status = "Healthy"
              health_status.message = "Resource is in use."
              return health_status
            end
            return health_status
          end

          for i, condition in ipairs(obj.status.conditions) do
            if condition.type == "LastAsyncOperation" then
              if condition.status == "False" then
                health_status.status = "Degraded"
                health_status.message = condition.message
                return health_status
              end
            end

            if condition.type == "Synced" then
              if condition.status == "False" then
                health_status.status = "Degraded"
                health_status.message = condition.message
                return health_status
              end
            end

            if contains({"Ready", "Healthy", "Offered", "Established"}, condition.type) then
              if condition.status == "True" then
                health_status.status = "Healthy"
                health_status.message = "Resource is up-to-date."
                return health_status
              end
            end
          end

          return health_status

      "crossform.io/xModule":
        health.lua: |
          local health_status = {
              status = "Progressing",
              message = "Provisioning ..."
          }
          local ready = false

          if obj.status == nil then
            return health_status
          end

          if obj.status.repository == nil then
            return health_status
          end

          if obj.status.repository.ok == nil then
            return health_status
          end

          if obj.status.repository.ok == false then
              health_status.status = "Degraded"
              health_status.message = obj.status.repository.message
              return health_status
          end

          for i, condition in ipairs(obj.status.conditions) do
              if condition.type == "LastAsyncOperation" then
                  if condition.status == "False" then
                      health_status.status = "Degraded"
                      health_status.message = condition.message
                      return health_status
                  end
              end

              if condition.type == "Synced" then
                  if condition.status == "False" then
                      health_status.status = "Degraded"
                      health_status.message = condition.message
                      return health_status
                  end
              end

              if condition.type == "Ready" then
                  if condition.status == "True" then
                      ready = true
                  end
              end
          end

          if ready == false then
              return health_status
          end

          if obj.hasErrors == false then
              return health_status
          end

          local errors = ""
          for k, v in pairs(obj.status.report) do
              if k == "inputsValidation" then
                  if v ~= "OK" then
                      health_status.status = "Degraded"
                      health_status.message = v
                      return health_status
                  end
              else
                  for kk, vv in pairs(v) do
                      if vv ~= "OK" then
                          errors = errors .. k .. "." .. kk .. ":" .. vv .. "\n"
                      end
                  end
              end
          end

          if errors ~= "" then
              health_status.status = "Degraded"
              health_status.message = errors
              return health_status
          end

          health_status.status = "Healthy"
          health_status.message = "Resource is up-to-date."
          return health_status
EOF
  ]

  dynamic "set" {
    for_each = {
      "configs.params.server\\.insecure"                                                  = "true"
      "configs.secret.argocdServerAdminPassword"                                          = bcrypt_hash.argo_pass.id
      "server.extraArgs[0]"                                                               = "--insecure"
      "server.service.type"                                                               = "NodePort"
      "server.ingressGrpc.isAWSALB"                                                       = false
      "server.ingressGrpc.enabled"                                                        = false
      "server.ingressGrpc.hostname"                                                       = "argo-grpc.${var.domain}"
      "server.ingressGrpc.ingressClassName"                                               = "alb"
      "server.ingressGrpc.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"             = "internet-facing"
      "server.ingressGrpc.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"       = "\\[{\"HTTPS\":443}\\]"
      "server.ingressGrpc.annotations.external-dns\\.kubernetes\\.io/enable"              = "false"
      "server.ingressGrpc.annotations.alb\\.ingress\\.kubernetes\\.io/load-balancer-name" = "argo-grpc"
      "server.ingressGrpc.awsALB.serviceType"                                             = "NodePort"
      "server.ingressGrpc.https"                                                          = false
      "server.configEnabled"                                                              = true
      "controller.metrics.enabled"                                                        = true
    }
    content {
      name  = set.key
      value = set.value
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  argo_global_params = {
    region       = var.region,
    cluster_name = var.cluster_name,
    account_id   = data.aws_caller_identity.current.account_id,
    argo_repo    = var.argo_repo,
    oidc_url     = var.oidc_url,
    oidc_arn     = var.oidc_arn,
    argo_branch  = var.argo_branch,
  }
}

resource "kubernetes_manifest" "argo_base" {
  depends_on = [helm_release.argo-cd]
  lifecycle {
    prevent_destroy = true
  }
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = {
      annotations = {
        "argocd.argoproj.io/sync-options" = "SkipDryRunOnMissingResource=true"
      }
      name      = "argo-base"
      namespace = "argo"
    }
    spec = {
      destination = {
        namespace = "argo"
        server    = "https://kubernetes.default.svc"
      }
      ignoreDifferences = [
        {
          group        = "datadoghq.com"
          jsonPointers = [
            "/spec/tags",
          ]
          kind = "DatadogMonitor"
        },
      ]
      project = "default"
      source  = {
        directory = {
          jsonnet = {
            extVars = [
              {
                name  = "repo_url"
                value = var.argo_repo
              },
              {
                name  = "revision",
                value = var.argo_branch
              }
            ]
          }
        }
        path           = "examples/argo-base"
        repoURL        = var.argo_repo
        targetRevision = var.argo_branch
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        retry = {
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "3m"
          }
          limit = 7
        }
        syncOptions = [
          "CreateNamespace=true",
          "ApplyOutOfSyncOnly=true",
          "RespectIgnoreDifferences=true",
          "ServerSideApply=true",
          "SkipDryRunOnMissingResource=true",
          "PrunePropagationPolicy=orphan"
        ]
      }
    }
  }
}


resource "kubernetes_config_map" "argo_ssh" {
  depends_on = [kubernetes_namespace.argo]
  metadata {
    name      = "repo-server-ssh-cm"
    namespace = "argo"
  }
  data = {
    ssh_config = <<EOF
Include /etc/ssh/ssh_config.d/*.conf
HOST *
StrictHostKeyChecking no
Host vs-ssh.visualstudio.com
HostkeyAlgorithms +ssh-rsa
PubkeyAcceptedAlgorithms +ssh-rsa
EOF
  }
}

resource "random_password" "argo_wf_client_secret" {
  length  = 32
  special = false
}

resource "random_string" "argo_wf_client_id" {
  length  = 16
  special = false
}

resource "kubernetes_secret_v1" "argo_wf_sso_secret" {
  metadata {
    name      = "argo-workflows-sso"
    namespace = "argo"
  }

  data = {
    client-id     = random_string.argo_wf_client_id.result
    client-secret = random_password.argo_wf_client_secret.result
  }
}


locals {
  repo_name      = split(".", split("/", var.argo_repo)[1])[0]
  org_name       = split("/", split(":", var.argo_repo)[1])[0]
  repo_full_name = "${local.org_name}/${local.repo_name}"
}


resource "kubernetes_cluster_role_v1" "argo_server" {
  metadata {
    name = "argocd-server-cluster-apps"
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create"]
  }
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications"]
    verbs      = ["create", "delete", "update", "patch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "argo_server" {
  metadata {
    name = "argocd-server-cluster-apps"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argo_server.metadata[0].name
  }
  subject {
    kind      = "User"
    name      = "admin"
    api_group = "rbac.authorization.k8s.io"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "argocd-server"
    namespace = "argo"
  }
}

resource "kubernetes_cluster_role_v1" "argo_notification" {
  metadata {
    name = "argocd-notifications-controller-cluster-apps"
  }

  rule {
    api_groups = [""]
    resources  = ["secrets", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications"]
    verbs      = ["get", "list", "watch", "update", "patch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "argo_notification" {
  metadata {
    name = "argocd-notifications-controller-cluster-apps"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argo_notification.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "argocd-notifications-controller"
    namespace = "argo"
  }
}

module "eks-kubeconfig" {
  source       = "hyperbadger/eks-kubeconfig/aws"
  version      = "2.0.0"
  cluster_name = var.cluster_name
}

resource "null_resource" "patch_default_project" {
  depends_on = [helm_release.argo-cd]
  provisioner "local-exec" {
    command     = "kubectl -n argo patch --type=merge AppProject default -p '{\"spec\":{\"sourceNamespaces\":[\"*\"]}}' --kubeconfig <(echo ${base64encode(module.eks-kubeconfig.kubeconfig)} | base64 -d)"
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "kubernetes_secret_v1" "argo_repo" {
  depends_on = [helm_release.argo-cd]
  metadata {
    name      = "argocd-repo"
    namespace = "argo"
    labels    = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = var.argo_repo
    sshPrivateKey = var.argo_ssh_key
  }
}
