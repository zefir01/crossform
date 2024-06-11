local lib = std.extVar('crossform');
local xr = std.extVar('xr');

local nameSuffix = '-'+ std.split(xr.metadata.uid, '-')[0];

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },

  role(name, assumeRolePolicy):: lib.resource('role-'+name, {
    apiVersion: 'iam.aws.crossplane.io/v1beta1',
    kind: 'Role',
    metadata: {
      name: name+nameSuffix,
    },
    spec: {
      forProvider: {
        assumeRolePolicyDocument: std.toString(assumeRolePolicy),
        tags: [
          {
            key: 'Name',
            value: name+nameSuffix,
          },
        ],
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  attachment(name, role, policy):: lib.resource('attachment-'+name, {
    apiVersion: 'iam.aws.crossplane.io/v1beta1',
    kind: 'RolePolicyAttachment',
    metadata: {
      name: name+nameSuffix,
    },
    spec: {
      forProvider: {
        policyArn: if std.type(policy)=='string' then policy else policy.status.atProvider.policyARN,
        roleName: role.metadata.name,
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  policy(name, document):: lib.resource('policy-'+name, {
    apiVersion: 'iam.aws.crossplane.io/v1beta1',
    kind: 'Policy',
    metadata: {
      name: name+nameSuffix,
    },
    spec: {
      forProvider: {
        name: name+nameSuffix,
        document: std.toString(document),
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  openIdConnectProvider(name, cluster):: lib.resource('openIdConnectProvider-'+name, {
    apiVersion: 'iam.aws.crossplane.io/v1beta1',
    kind: 'OpenIDConnectProvider',
    metadata: {
      name: name+nameSuffix,
    },
    spec: {
      forProvider: {
        clientIDList: [
          'sts.amazonaws.com',
        ],
        thumbprintList: [
          '9e99a48a9960b14926bb7f3b02e22da2b0ab7280',
        ],
        url: cluster.status.atProvider.identity.oidc.issuer,
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  irsa(name, saName, namespace, oidcUrl, oidcArn):: $.role(name, std.toString({
    Version: '2012-10-17',
    Statement: [
      {
        Effect: 'Allow',
        Principal: {
          Federated: oidcArn,
        },
        Action: 'sts:AssumeRoleWithWebIdentity',
        Condition: {
          StringEquals: {
            [std.strReplace(oidcUrl, 'https://', '')+':aud']: 'sts.amazonaws.com',
            [std.strReplace(oidcUrl, 'https://', '')+':sub']: 'system:serviceaccount:'+namespace+':'+saName,
          },
        },
      },
    ],
  })),
}