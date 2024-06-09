local lib = std.extVar('crossform');
local xr = std.extVar('xr');

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },
  region: 'us-east-1',
  withRegion(region):: ${ region: region },

  eks(name, subnets, role, securityGroups):: {
    apiVersion: 'eks.aws.crossplane.io/v1beta1',
    kind: 'Cluster',
    metadata: {
      name: xr.metadata.name+'-'+name,
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
          securityGroupId: [
            if std.type(sg) == 'object' then sg.status.atProvider.SecurityGroupID else sg
            for sg in securityGroups
          ],
        },
        version: '1.21',
      },
      writeConnectionSecretToRef: {
        name: 'cluster-conn',
        namespace: 'default',
      },
      providerConfigRef: {
        name: 'example',
      },
    },
  },
}