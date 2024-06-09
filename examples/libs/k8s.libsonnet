local lib = std.extVar('crossform');

local observed = std.extVar('observed');
local requested = std.extVar('requested');
local input = std.extVar('input');
local xr = std.extVar('xr');

local getObserved(id) = std.get(observed, id, {});

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },

  object(id, obj, name=id, orphan=false):: lib.resource(id, {
    apiVersion: 'kubernetes.crossplane.io/v1alpha2',
    kind: 'Object',
    metadata: {
      [if name!=null then 'name']: xr.metadata.name+'-'+name,
    },
    spec: {
      [if orphan then 'deletionPolicy']: 'Orphan',
      forProvider: {
        manifest: (if getObserved(id)=={} then obj else std.mergePatch(obj, {
          metadata: {
            ownerReferences: [
              {
                apiVersion: 'kubernetes.crossplane.io/v1alpha2',
                blockOwnerDeletion: true,
                controller: true,
                kind: 'Object',
                name: getObserved(id).metadata.name,
                uid: getObserved(id).metadata.uid,
              },
            ],
          },
        }
        )),
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  module(id, path, revision='main', inputs=null):: lib.resource(id, {
    apiVersion: 'crossform.io/v1alpha1',
    kind: 'xModule',
    metadata: {
      name: xr.metadata.name+'-'+id,
    },
    spec: {
      repository: 'git@github.com:zefir01/crossform.git',
      revision: revision,
      path: path,
      [if inputs!=null then 'inputs']: inputs,
    },
  }
  ),
}