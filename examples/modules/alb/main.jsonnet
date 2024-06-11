local lib = std.extVar('crossform');

local iam = import '../../libs/iam.libsonnet';

local helmProviderConfigName = lib.input('helmProviderConfigName', 'string');

{
  helmProviderConfigName: helmProviderConfigName,
  policy: iam.policy('alb', importstr 'policy.json' ),
}