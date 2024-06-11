local lib = std.extVar('crossform');

local helm = import '../../libs/helm.libsonnet';

local region = lib.input('region', 'string');
local awsProviderConfig = lib.input('awsProviderConfig', 'string');
local accountId = lib.input('accountId', 'string');
local vpcId = lib.input('vpcId', 'string');
local privateSubnets = lib.input('privateSubnets', schema={
  type: 'array',
  items: {
    type: 'string',
  },
}
);
local publicSubnets = lib.input('privateSubnets', schema={
  type: 'array',
  items: {
    type: 'string',
  },
}
);

local mapUsers = lib.input('mapUsers', default=[], schema={
  type: 'array',
  items: {
    type: 'object',
    properties: {
      arn: {
        type: 'string',
      },
      username: {
        type: 'string',
      },
      groups: {
        type: 'array',
        items: {
          type: 'string',
        },
      },
    },
  },
});

local mapRoles = lib.input('mapRoles', default=[], schema={
  type: 'array',
  items: {
    type: 'object',
    properties: {
      arn: {
        type: 'string',
      },
      groups: {
        type: 'array',
        items: {
          type: 'string',
        },
      },
    },
  },
});

local iam = (import '../../libs/iam.libsonnet').withProviderConfig(awsProviderConfig.value);
local vpc = (import '../../libs/vpc.libsonnet').withProviderConfig(awsProviderConfig.value).withRegion(region.value);
local k = (import '../../libs/eks.libsonnet').withProviderConfig(awsProviderConfig.value).withRegion(region.value);

local eks = iam.role('eks', {
  Version: '2012-10-17',
  Statement: [
    {
      Effect: 'Allow',
      Principal: {
        Service: [
          'eks.amazonaws.com',
        ],
      },
      Action: [
        'sts:AssumeRole',
      ],
    },
  ],
});
local node = iam.role('node', {
  Version: '2012-10-17',
  Statement: [
    {
      Effect: 'Allow',
      Principal: {
        Service: [
          'ec2.amazonaws.com',
        ],
      },
      Action: [
        'sts:AssumeRole',
      ],
    },
  ],
});

local eksAttachment = iam.attachment('eks', eks, 'arn:aws:iam::aws:policy/AmazonEKSClusterPolicy');
local nodeAttachment1 = iam.attachment('node1', node, 'arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy');
local nodeAttachment2 = iam.attachment('node2', node, 'arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly');
local nodeAttachment3 = iam.attachment('node3', node, 'arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy');
local nodeAttachment4 = iam.attachment('node4', node, 'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore');

local eksSg = vpc.securityGroup('eks', vpcId.value, description='Eks cluster SG');

local cluster = k.eks('test1', privateSubnets.value, eks, [eksSg], connectionSecret={
  name: 'cluster-conn',
  namespace: 'default',
});
local nodeGroup = k.nodeGroup('main', cluster, privateSubnets.value, node);

local coredns = k.addon('coredns', cluster, 'coredns', 'v1.11.1-eksbuild.4');
local vpccni = k.addon('vpc-cni', cluster, 'vpc-cni', 'v1.16.0-eksbuild.1');

local providerConfig = k.k8sProviderConfig('test1', cluster);

local awsAuth = k.awsAuth('auth', node, providerConfig, mapUsers.value, mapRoles.value);

local getOidcArn(url) =
  local t = std.strReplace(url, 'https://', '');
    'arn:aws:iam::'+accountId.value+':oidc-provider/'+t;

{
  region: region,
  awsProviderConfig: awsProviderConfig,
  accountId: accountId,
  vpcId: vpcId,
  privateSubnets: privateSubnets,
  publicSubnets: publicSubnets,
  eks: eks,
  node: node,
  eksAttachment: eksAttachment,
  nodeAttachment1: nodeAttachment1,
  nodeAttachment2: nodeAttachment2,
  nodeAttachment3: nodeAttachment3,
  nodeAttachment4: nodeAttachment4,
  eksSg: eksSg,
  cluster: cluster,
  nodeGroup: nodeGroup,
  coredns: coredns,
  vpccni: vpccni,
  providerConfig: providerConfig,
  providerConfigName: lib.output('providerConfigName', providerConfig.metadata.name),
  awsAuth: awsAuth,
  mapUsers: mapUsers,
  mapRoles: mapRoles,
  helmProviderConfig: helm.providerConfig('eks', cluster),
  helmProviderConfigName: lib.output('helmProviderConfigName', $.helmProviderConfig.metadata.name),
  oidcUrl: lib.output('oidcUrl', cluster.status.atProvider.identity.oidc.issuer),
  openIdConnectProvider: iam.openIdConnectProvider('eks', cluster),
  oidcArn: lib.output('oidcArn', getOidcArn(cluster.status.atProvider.identity.oidc.issuer)),
}