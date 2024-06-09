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
}