local lib = std.extVar('crossform');

local test1 = lib.resource('test1', {
  apiVersion: 'kubernetes.crossplane.io/v1alpha2',
  kind: 'Object',
  metadata: {
    name: 'sample-namespace',
  },
  spec: {
    forProvider: {
      manifest: {
        apiVersion: 'v1',
        kind: 'Namespace',
        metadata: {
          labels: {
            example: 'true',
          },
        },
      },
    },
    providerConfigRef: {
      name: 'kubernetes-provider',
    },
  },
});

local request1 = lib.request('test-request1', 'crossform.io/v1alpha1', 'xmodule', 'example-claim-p8nzs');

local test2 = lib.resource('test2', {
  apiVersion: 'kubernetes.crossplane.io/v1alpha2',
  kind: 'Object',
  metadata: {
    name: 'sample-namespace-'+test1.status.atProvider.manifest.apiVersion,
  },
  spec: {
    forProvider: {
      manifest: {
        apiVersion: 'v1',
        kind: 'Namespace',
        metadata: {
          labels: {
            example: 'true',
            //test1: request1.result.spec.claimRef.kind
          },
        },
      },
    },
    providerConfigRef: {
      name: 'kubernetes-provider',
    },
  },
});

local xr = lib.resource('xr1', std.extVar('xr'));
local input1 = lib.input('test1', 'string');

{
  test1: test1,
  test2: test2,
  request1: request1,
  output1: lib.output('test1', input1.value),
  input1: input1
}