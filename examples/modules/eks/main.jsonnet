local lib = std.extVar('crossform');

local region = lib.input('region', 'string');
local awsProviderConfig = lib.input('awsProviderConfig', 'string');
local accountId = lib.input('accountId', 'string');
local vpcId = lib.input('vpcId', 'string');

local iam = (import '../../libs/iam.libsonnet').withProviderConfig(awsProviderConfig.value);
local vpc = (import '../../libs/vpc.libsonnet').withProviderConfig(awsProviderConfig.value).withRegion(region.value);

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

local eksSg = vpc.securityGroup('eks', vpcId.value);

{
  region: region,
  awsProviderConfig: awsProviderConfig,
  accountId: accountId,
  vpcId: vpcId,
  eks: eks,
  node: node,
  eksAttachment: eksAttachment,
  nodeAttachment1: nodeAttachment1,
  nodeAttachment2: nodeAttachment2,
  nodeAttachment3: nodeAttachment3,
  eksSg: eksSg
}