local lib = std.extVar('crossform');

local observed = std.extVar('observed');
local requested = std.extVar('requested');
local input = std.extVar('input');
local xr = std.extVar('xr');

local getObserved(id) = std.get(observed, id, {});

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },

  object(id, name, obj):: lib.resource(id, {
    apiVersion: 'kubernetes.crossplane.io/v1alpha2',
    kind: 'Object',
    spec: {
      forProvider: {
        manifest: if getObserved(id)=={} then obj else std.mergePatch(obj, {
          metadata: {
            ownerReferences: [
              {
                apiVersion: 'kubernetes.crossplane.io/v1alpha2',
                blockOwnerDeletion: false,
                controller: false,
                kind: 'Object',
                name: getObserved(id).metadata.name,
                uid: getObserved(id).metadata.uid,
              },
            ],
          },
        }
        ),
      },
    },
  })+if $.providerConfig!=null then {
    withProviderConfigRef:: $.providerConfig,
  } else {},
}