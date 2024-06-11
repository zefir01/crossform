local lib = std.extVar('crossform');
local main = import 'main.jsonnet';

local k8s = (import '../libs/k8s.libsonnet').withProviderConfig(main.providerConfig.metadata.name);


{
  network: k8s.module('vpc', 'examples/modules/vpc', inputs={
    region: 'us-east-2',
    awsProviderConfig: main.awsProviderConfig.metadata.name,
    cidr: '10.100.0.0/16',
  }),
  eks: k8s.module('eks', 'examples/modules/eks', inputs={
    region: 'us-east-2',
    awsProviderConfig: main.awsProviderConfig.metadata.name,
    accountId: main.accountId.value,
    vpcId: $.network.status.outputs.vpcId,
    privateSubnets: $.network.status.outputs.privateSubnets,
    publicSubnets: $.network.status.outputs.publicSubnets,
    mapUsers: [
      {
        arn: 'arn:aws:iam::482235484697:user/peter.stukalov@dr.paygears.com',
        username: 'peter.stukalov',
        groups: ['system:masters'],
      },
    ],
  }),
  alb: k8s.module('alb', 'examples/modules/alb', inputs={
    awsProviderConfig: main.awsProviderConfig.metadata.name,
    helmProviderConfig: $.eks.status.outputs.helmProviderConfigName,
    oidcUrl: $.eks.status.outputs.oidcUrl,
    oidcArn: $.eks.status.outputs.oidcArn,
    clusterName: $.eks.status.outputs.clusterName,
  }),
}