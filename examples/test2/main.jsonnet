local lib = std.extVar('crossform');
local observed = std.extVar('observed');


local k8sProviderConfig = lib.resource('providerConfig', {
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

local awsProviderConfig = lib.resource('providerConfigAws', {
  apiVersion: 'aws.crossplane.io/v1beta1',
  kind: 'ProviderConfig',
  metadata: {
    name: 'default',
  },
  spec: {
    credentials: {
      source: 'InjectedIdentity',
    },
  },
})+{
  crossform+:: {
    ready: true,
  },
};

local k8s = (import '../libs/k8s.libsonnet').withProviderConfig(k8sProviderConfig.metadata.name);

local test1 = k8s.object('test1', {
  apiVersion: 'v1',
  kind: 'Namespace',
  metadata: {
    labels: {
      example: 'true',
    },
  },
});

local request1 = lib.request('test-request1', 'crossform.io/v1alpha1', 'xmodule', 'example-claim-p8nzs');

local test2 = k8s.object('test2', {
  apiVersion: 'v1',
  kind: 'Namespace',
  metadata: {
    labels: {
      example: 'true',
      //test1: request1.result.spec.claimRef.kind
    },
  },
}
);

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

local rdsSecret = k8s.object('rds-secret', {
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
}
);


{
  providerConfig: k8sProviderConfig,
  awsProviderConfig: awsProviderConfig
  //test1: test1,
  //test2: test2,
  //request1: request1,
  //output1: lib.output('test1', input1.value),
  //input1: input1,
  //rdsSecret: rdsSecret,
  //rds: rds,
}