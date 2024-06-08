local lib = std.extVar('crossform');

local awsProviderConfig = lib.resource('providerConfigAws', {
  apiVersion: 'aws.crossplane.io/v1beta1',
  kind: 'ProviderConfig',
  metadata: {
    name: 'default',
  },
  spec: {
    credentials: {
      source: 'InjectedIdentity',
    },
  },
})+{
  crossform+:: {
    ready: true,
  },
};


local k8s = (import '../libs/k8s.libsonnet').withProviderConfig('kubernetes-local');


{
  awsProviderConfig: awsProviderConfig,
  network: k8s.module('vpc', 'examples/modules/vpc', inputs={
    region: 'us-east-2',
    awsProviderConfig: 'default',
    cidr: '10.100.0.0/16',
  }),
}