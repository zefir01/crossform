local lib = std.extVar('crossform');
local ip = import '../libs/ip.libsonnet';

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

local cidr='10.100.0.0/16';
local networks=ip.calcNetworks(cidr, [18,18,18,20,20,20]);
local testVpc = vpc.vpc('test', cidr);
local subnetA=vpc.subnet('A', networks[0].cidr, 'A', testVpc);

{
  testVpc: testVpc,
  subnetA: subnetA
}