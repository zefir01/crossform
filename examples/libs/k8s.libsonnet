local lib = std.extVar('crossform');

local observed = std.extVar('observed');
local requested = std.extVar('requested');
local input = std.extVar('input');
local xr = std.extVar('xr');

local getObserved(id) = std.get(observed, id, {});

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },

  object(id, obj, name=id):: lib.resource(id, {
    apiVersion: 'kubernetes.crossplane.io/v1alpha2',
    kind: 'Object',
    metadata: {
      [if name!=null then 'name']: name,
      annotations: {
        'argocd.argoproj.io/sync-options': 'Prune=false,Delete=false',
      },
    },
    spec: {
      forProvider: {
        manifest: (if getObserved(id)=={} then obj else std.mergePatch(obj, {
          metadata: {
            ownerReferences: [
              {
                apiVersion: 'kubernetes.crossplane.io/v1alpha2',
                blockOwnerDeletion: false,
                controller: true,
                kind: 'Object',
                name: getObserved(id).metadata.name,
                uid: getObserved(id).metadata.uid,
              },
            ],
          },
        }
        ))+{
          metadata+: {
            annotations+: {
              'argocd.argoproj.io/sync-options': 'Prune=false,Delete=false',
            },
          },
        },
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),
}