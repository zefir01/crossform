local lib = std.extVar('crossform');
local ip = import '../../libs/ip.libsonnet';

local region = lib.input('region', 'string');
local awsProviderConfig = lib.input('awsProviderConfig', 'string');
local cidr = lib.input('cidr', 'string');
local clusterName = lib.input('clusterName', 'string');

local vpc = (import '../../libs/vpc.libsonnet').withProviderConfig(awsProviderConfig.value).withRegion(region.value);

local tagsPublic = {
  'kubernetes.io/role/elb': '1',
  type: 'public',
  ['kubernetes.io/cluster/'+clusterName.value]: 'shared',
};

local tagsPrivate = {
  'kubernetes.io/role/internal-elb': '1',
  type: 'public',
  ['kubernetes.io/cluster/'++clusterName.value]: 'shared',
};

local networks = ip.calcNetworks(cidr.value, [18, 18, 18, 20, 20, 20]);
local testVpc = vpc.vpc('test', cidr.value);
local privateSubnetA = vpc.subnet('private-a', networks[0].cidr, 'a', testVpc);
local privateSubnetB = vpc.subnet('private-b', networks[1].cidr, 'b', testVpc);
local privateSubnetC = vpc.subnet('private-c', networks[2].cidr, 'c', testVpc);

local publicSubnetA = vpc.subnet('public-a', networks[3].cidr, 'a', testVpc, private=false);
local publicSubnetB = vpc.subnet('public-b', networks[4].cidr, 'b', testVpc, private=false);
local publicSubnetC = vpc.subnet('public-c', networks[5].cidr, 'c', testVpc, private=false);

local eipA = vpc.eip('a');
local eipB = vpc.eip('b');
local eipC = vpc.eip('c');

local natA = vpc.natGateway('a', publicSubnetA, eipA);
local natB = vpc.natGateway('b', publicSubnetB, eipB);
local natC = vpc.natGateway('c', publicSubnetC, eipC);
local internetGateway = vpc.internetGateway('default', testVpc);

local privateRouteTableA = vpc.routeTable('private-a', [vpc.routeNatGateway('0.0.0.0/0', natA)], [privateSubnetA], testVpc);
local privateRouteTableB = vpc.routeTable('private-b', [vpc.routeNatGateway('0.0.0.0/0', natB)], [privateSubnetB], testVpc);
local privateRouteTableC = vpc.routeTable('private-c', [vpc.routeNatGateway('0.0.0.0/0', natC)], [privateSubnetC], testVpc);

local publicRouteTable = vpc.routeTable('public', [vpc.routeGateway('0.0.0.0/0', internetGateway)], [publicSubnetA, publicSubnetB, publicSubnetC], testVpc);

{
  clusterName: clusterName,
  region: region,
  awsProviderConfig: awsProviderConfig,
  cidr: cidr,
  testVpc: testVpc,
  privateSubnetA: privateSubnetA,
  privateSubnetB: privateSubnetB,
  privateSubnetC: privateSubnetC,
  publicSubnetA: publicSubnetA,
  publicSubnetB: publicSubnetB,
  publicSubnetC: publicSubnetC,
  eipA: eipA,
  eipB: eipB,
  eipC: eipC,
  natA: natA,
  natB: natB,
  natC: natC,
  internetGateway: internetGateway,
  privateRouteTableA: privateRouteTableA,
  privateRouteTableB: privateRouteTableB,
  privateRouteTableC: privateRouteTableC,
  publicRouteTable: publicRouteTable,
  vpcId: lib.output('vpcId', testVpc.status.atProvider.vpcId),
  natIps: lib.output('natIps', [
    eipA.status.atProvider.publicIp,
    eipB.status.atProvider.publicIp,
    eipC.status.atProvider.publicIp,
  ]),
  privateSubnets: lib.output('privateSubnets', [
    privateSubnetA.status.atProvider.subnetId,
    privateSubnetB.status.atProvider.subnetId,
    privateSubnetC.status.atProvider.subnetId,
  ]),
  publicSubnets: lib.output('publicSubnets', [
    publicSubnetA.status.atProvider.subnetId,
    publicSubnetB.status.atProvider.subnetId,
    publicSubnetC.status.atProvider.subnetId,
  ]),
}