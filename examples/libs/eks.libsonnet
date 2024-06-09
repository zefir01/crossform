local lib = std.extVar('crossform');
local xr = std.extVar('xr');

local nameSuffix = '-'+ std.split(xr.metadata.uid, '-')[0];

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },
  region: 'us-east-1',
  withRegion(region):: ${ region: region },

  eks(name, subnets, role, securityGroups):: lib.resource('eks-cluster-'+name, {
    apiVersion: 'eks.aws.crossplane.io/v1beta1',
    kind: 'Cluster',
    metadata: {
      name: name+nameSuffix,
    },
    spec: {
      forProvider: {
        region: $.region,
        roleArn: if std.type(role)=='object' then role.status.atProvider.arn else role,
        resourcesVpcConfig: {
          endpointPrivateAccess: true,
          endpointPublicAccess: true,
          subnetIds: [
            if std.type(subnet) == 'object' then subnet.status.atProvider.subnetId else subnet
            for subnet in subnets
          ],
          securityGroupIds: [
            if std.type(sg) == 'object' then sg.status.atProvider.SecurityGroupID else sg
            for sg in securityGroups
          ],
        },
        version: '1.29',
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),
}