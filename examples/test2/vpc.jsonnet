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

local vpc = (import '../libs/vpc.libsonnet').withProviderConfig(awsProviderConfig.metadata.name);

local testVpc = vpc.vpc('test', '10.100.0.0/16');

{
  testVpc: testVpc
}