local lib = std.extVar('crossform');
local xr = std.extVar('xr');

local nameSuffix = '-'+ std.split(xr.metadata.uid, '-')[0];

{
  provider():: lib.resource('provider-helm', {
    apiVersion: 'pkg.crossplane.io/v1',
    kind: 'Provider',
    metadata: {
      name: 'provider-helm',
    },
    spec: {
      package: 'xpkg.upbound.io/crossplane-contrib/provider-helm:v0.17.0',
      runtimeConfigRef: {
        apiVersion: 'pkg.crossplane.io/v1beta1',
        kind: 'DeploymentRuntimeConfig',
        name: 'provider-helm',
      },
    },
  }),

  runtimeConfig():: lib.resource('provider-helm-runtime-config', {
    apiVersion: 'pkg.crossplane.io/v1beta1',
    kind: 'DeploymentRuntimeConfig',
    metadata: {
      name: 'provider-helm',
    },
    spec: {
      serviceAccountTemplate: {
        metadata: {
          name: 'provider-helm',
        },
      },
    },
  }),

  crb():: lib.resource('provider-helm-cluster-admin', {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'provider-helm-cluster-admin',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'provider-helm',
        namespace: 'crossplane-system',
      },
    ],
    roleRef: {
      kind: 'ClusterRole',
      name: 'cluster-admin',
      apiGroup: 'rbac.authorization.k8s.io',
    },
  }),
}