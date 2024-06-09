local lib = std.extVar('crossform');
local xr = std.extVar('xr');

local nameSuffix = '-'+ std.split(xr.metadata.uid, '-')[0];

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },
  region: 'us-east-1',
  withRegion(region):: ${ region: region },

  eks(name, subnets, role, securityGroups, connectionSecret=null):: lib.resource('eks-cluster-'+name, {
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
            if std.type(sg) == 'object' then sg.status.atProvider.securityGroupID else sg
            for sg in securityGroups
          ],
        },
        version: '1.29',
      },
      [if connectionSecret!=null then 'writeConnectionSecretToRef']: connectionSecret,
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  nodeGroup(name, cluster, subnets, role):: lib.resource('node-group-'+name, {
    apiVersion: 'eks.aws.crossplane.io/v1alpha1',
    kind: 'NodeGroup',
    metadata: {
      name: name+nameSuffix,
    },
    spec: {
      forProvider: {
        region: $.region,
        clusterName: cluster.metadata.name,
        subnets: [
          if std.type(subnet) == 'object' then subnet.status.atProvider.subnetId else subnet
          for subnet in subnets
        ],
        nodeRole: if std.type(role)=='object' then role.status.atProvider.arn else role,
        scalingConfig: {
          desiredSize: 1,
          maxSize: 1,
          minSize: 1,
        },
        updateConfig: {
          maxUnavailablePercentage: 50,
          force: true,
        },
        instanceTypes: ['t3.medium'],
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  addon(name, cluster, addonName, addonVersion):: lib.resource('addon-'+name, {
    apiVersion: 'eks.aws.crossplane.io/v1alpha1',
    kind: 'Addon',
    metadata: {
      name: name+nameSuffix,
    },
    spec: {
      forProvider: {
        region: $.region,
        addonName: addonName,
        addonVersion: addonVersion,
        clusterName: cluster.metadata.name,
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  providerConfig(name, eks):: lib.resource('k8s-providerConfig-'+name, {
    apiVersion: 'kubernetes.crossplane.io/v1alpha1',
    kind: 'ProviderConfig',
    metadata: {
      name: name+nameSuffix,
    },
    spec: {
      credentials: {
        source: 'Secret',
        secretRef: {
          namespace: eks.spec.writeConnectionSecretToRef.namespace,
          name: eks.spec.writeConnectionSecretToRef.name,
          key: 'kubeconfig',
        },
      },
    },
  }),
}