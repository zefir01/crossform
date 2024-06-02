local lib = std.extVar('crossform');

{
  object(id, obj):: lib.resource(id, {
    apiVersion: 'kubernetes.crossplane.io/v1alpha2',
    kind: 'Object',
    spec: {
      forProvider: {
        manifest: obj
      },
    },
  })+{
    withProviderConfigRef:: function(ref) $
  }
}