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

local cidr = '10.100.0.0/16';
local networks = ip.calcNetworks(cidr, [18, 18, 18, 20, 20, 20]);
local testVpc = vpc.vpc('test', cidr);
local privateSubnetA = vpc.subnet('private-a', networks[0].cidr, 'a', testVpc);
local privateSubnetB = vpc.subnet('private-b', networks[1].cidr, 'b', testVpc);
local privateSubnetC = vpc.subnet('private-c', networks[2].cidr, 'c', testVpc);

local publicSubnetA = vpc.subnet('public-a', networks[3].cidr, 'a', testVpc, private=false);
local publicSubnetB = vpc.subnet('public-b', networks[4].cidr, 'b', testVpc, private=false);
local publicSubnetC = vpc.subnet('public-c', networks[5].cidr, 'c', testVpc, private=false);

{
  awsProviderConfig: awsProviderConfig,
  testVpc: testVpc,
  privateSubnetA: privateSubnetA,
  privateSubnetB: privateSubnetB,
  privateSubnetC: privateSubnetC,
  publicSubnetA: publicSubnetA,
  publicSubnetB: publicSubnetB,
  publicSubnetC: publicSubnetC
}