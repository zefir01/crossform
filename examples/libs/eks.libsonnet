local lib = std.extVar('crossform');
local xr = std.extVar('xr');

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },
  region: 'us-east-1',
  withRegion(region):: ${ region: region },

  eks(name, subnets)::{
    apiVersion: 'eks.aws.crossplane.io/v1beta1',
    kind: 'Cluster',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        region: $.region,
        roleArnRef: {
          name: 'somerole',
        },
        resourcesVpcConfig: {
          endpointPrivateAccess: true,
          endpointPublicAccess: true,
          subnetIds: [
            subnet.status.atProvider.subnetId for subnet in subnets
          ],
          securityGroupIdRefs: [
            {
              name: 'sample-cluster-sg',
            }
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
  }
}