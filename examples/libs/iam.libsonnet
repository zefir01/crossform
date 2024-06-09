local lib = std.extVar('crossform');
local xr = std.extVar('xr');

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },

  role(name, assumeRolePolicy):: lib.resource('role-'+name, {
    apiVersion: 'iam.aws.crossplane.io/v1beta1',
    kind: 'Role',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        assumeRolePolicyDocument: std.toString(assumeRolePolicy),
        tags: [
          {
            key: 'Name',
            value: xr.metadata.name+'-'+name,
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
      name: xr.metadata.name+'-'+name,
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
    kind: 'RolePolicyAttachment',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        name: xr.metadata.name+'-'+name,
        document: std.toString(document),
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),
}