local lib = std.extVar('crossform');

local awsProviderConfig = lib.input('awsProviderConfig', 'string');
local helmProviderConfigName = lib.input('helmProviderConfig', 'string');

local iam = (import '../../libs/iam.libsonnet').withProviderConfig(awsProviderConfig.value);
local helm = (import '../../libs/helm.libsonnet').withProviderConfigName(helmProviderConfigName.value);

{
  awsProviderConfig: awsProviderConfig,
  helmProviderConfigName: helmProviderConfigName,
  oidcUrl: lib.input('oidcUrl', 'string'),
  oidcArn: lib.input('oidcArn', 'string'),
  clusterName: lib.input('clusterName', 'string'),
  policy: iam.policy('alb', importstr 'policy.json' ),
  role: iam.irsa('alb', 'aws-alb-ingress-controller', 'kube-system', $.oidcUrl.value, $.oidcArn.value),
  attachment: iam.attachment('alb', $.role, $.policy),
  release: helm.release('alb', 'aws-load-balancer-controller', 'https://aws.github.io/eks-charts', '1.8.1', 'kube-system', {
    clusterName: $.clusterName.value,
    serviceAccount: {
      name: 'aws-alb-ingress-controller',
      annotations: {
        'eks.amazonaws.com/role-arn': $.role.status.atProvider.arn,
      },
    },
  }),
}