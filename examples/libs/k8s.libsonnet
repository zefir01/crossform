local lib = std.extVar('crossform');

local observed = std.extVar('observed');
local requested = std.extVar('requested');
local input = std.extVar('input');
local xr = std.extVar('xr');

local getObserved(id) = std.get(observed, id, {});

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },

  object(id, obj):: lib.resource(id, {
    apiVersion: 'kubernetes.crossplane.io/v1alpha2',
    kind: 'Object',
    spec: {
      forProvider: {
        manifest: if getObserved(id)=={} then obj else std.mergePatch(obj, {
          apiVersion: $.apiVersion,
          blockOwnerDeletion: false,
          controller: false,
          kind: $.kind,
          name: $.metadata.name,
          uid: getObserved(id).metadata.uid,
        }),
      },
    },
  })+if $.providerConfig!=null then {
    withProviderConfigRef:: $.providerConfig,
  } else {},
}