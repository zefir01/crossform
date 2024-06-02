local lib = std.extVar('crossform');
local observed = std.extVar('observed');

local providerConfig = lib.resource('providerConfig', {
  apiVersion: 'kubernetes.crossplane.io/v1alpha1',
  kind: 'ProviderConfig',
  metadata: {
    name: 'kubernetes-local',
  },
  spec: {
    credentials: {
      source: 'InjectedIdentity',
    },
  },
});

local test1_observed=std.get(observed, 'test1');
local test1 = lib.resource('test1', {
  apiVersion: 'kubernetes.crossplane.io/v1alpha2',
  kind: 'Object',
  metadata: {
    name: 'sample-namespace',
  },
  spec: {
    forProvider: {
      manifest: {
        apiVersion: 'v1',
        kind: 'Namespace',
        metadata: {
          labels: {
            example: 'true',
          },
          [if test1_observed!=null then 'ownerReferences']: [
            {
              apiVersion: $.apiVersion,
              blockOwnerDeletion: false,
              controller: false,
              kind: $.kind,
              name: $.metadata.name,
              uid: test1_observed.metadata.uid,
            }
          ]
        },
      },
    },
    providerConfigRef: {
      name: providerConfig.metadata.name,
    },
  },
});

local request1 = lib.request('test-request1', 'crossform.io/v1alpha1', 'xmodule', 'example-claim-p8nzs');

local test2 = lib.resource('test2', {
  apiVersion: 'kubernetes.crossplane.io/v1alpha2',
  kind: 'Object',
  metadata: {
    name: 'sample-namespace-'+test1.status.atProvider.manifest.apiVersion,
  },
  spec: {
    forProvider: {
      manifest: {
        apiVersion: 'v1',
        kind: 'Namespace',
        metadata: {
          labels: {
            example: 'true',
            //test1: request1.result.spec.claimRef.kind
          },
        },
      },
    },
    providerConfigRef: {
      name: providerConfig.metadata.name,
    },
  },
});

local xr = lib.resource('xr1', std.extVar('xr'));
local input1 = lib.input('test1', 'string');

local rds = lib.resource('rds1', {
  apiVersion: 'rds.aws.crossplane.io/v1alpha1',
  kind: 'DBInstance',
  metadata: {
    name: 'rds1',
  },
  spec: {
    forProvider: {
      region: 'us-east-1',
      allocatedStorage: 20,
      autoMinorVersionUpgrade: true,
      autogeneratePassword: true,
      backupRetentionPeriod: 14,
      dbInstanceClass: 'db.t3.micro',
      dbName: 'example',
      engine: 'postgres',
      engineVersion: '16.1',
      allowMajorVersionUpgrade: true,
      masterUsername: 'adminuser',
      masterUserPasswordSecretRef: {
        key: 'password',
        name: 'example-dbinstance',
        namespace: 'crossplane-system',
      },
      preferredBackupWindow: '7:00-8:00',
      preferredMaintenanceWindow: 'Sat:8:00-Sat:11:00',
      publiclyAccessible: false,
      skipFinalSnapshot: true,
      storageEncrypted: false,
      storageType: 'gp2',
      applyImmediately: true,
      deleteAutomatedBackups: false,
    },
    writeConnectionSecretToRef: {
      name: 'example-dbinstance-out',
      namespace: 'default',
    },
    providerConfigRef: {
      name: 'default',
    },
  },
});

local rdsSecret = lib.resource('rdsSecret', {
  apiVersion: 'kubernetes.crossplane.io/v1alpha2',
  kind: 'Object',
  metadata: {
    name: 'rds-secret',
  },
  spec: {
    forProvider: {
      manifest: {
        apiVersion: 'v1',
        kind: 'Secret',
        metadata: {
          name: 'example-dbinstance',
          namespace: 'crossplane-system',
        },
        type: 'Opaque',
        data: {
          password: 'dGVzdFBhc3N3b3JkITEyMw==',
        },
      },
    },
    providerConfigRef: {
      name: 'kubernetes-provider',
    },
  },
}
);

{
  providerConfig: providerConfig,
  test1: test1,
  test2: test2,
  request1: request1,
  output1: lib.output('test1', input1.value),
  input1: input1,
  rdsSecret: rdsSecret,
  rds: rds
}