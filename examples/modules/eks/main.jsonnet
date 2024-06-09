local lib = std.extVar('crossform');

local region = lib.input('region', 'string');
local awsProviderConfig = lib.input('awsProviderConfig', 'string');
local accountId = lib.input('accountId', 'string');

local iam = (import '../../libs/iam.libsonnet').withProviderConfig(awsProviderConfig.value);
local vpc = (import '../../libs/vpc.libsonnet').withProviderConfig(awsProviderConfig.value).withRegion(region.value);

local role = iam.role('eks', {
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

local attachment = iam.attachment('eks', role, 'arn:aws:iam::aws:policy/AmazonEKSClusterPolicy');

{
  region: region,
  awsProviderConfig: awsProviderConfig,
  accountId: accountId,
  role: role,
  attachment: attachment,
}