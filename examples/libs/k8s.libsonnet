local lib = std.extVar('crossform');

local observed = std.extVar('observed');
local requested = std.extVar('requested');
local input = std.extVar('input');
local xr = std.extVar('xr');

local getObserved(id) = std.get(observed, id, {});

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },

  object(id, obj, name=id, wave=null):: lib.resource(id, {
    apiVersion: 'kubernetes.crossplane.io/v1alpha2',
    kind: 'Object',
    [if name!=null || wave!=null then 'metadata']: {
      name: name,
      [if wave != null then 'annotations']: {
        'argocd.argoproj.io/sync-wave': std.toString(wave),
      }
    },
    spec: {
      forProvider: {
        manifest: if getObserved(id)=={} then obj else std.mergePatch(obj, {
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
        ),
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),
}