local lib = std.extVar('crossform');
local xr = std.extVar('xr');

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },
  region: 'us-east-1',
  withRegion(region):: ${ region: region },

  vpc(name, cidr):: lib.resource('vpc-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'VPC',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        region: $.region,
        cidrBlock: cidr,
        enableDnsSupport: true,
        enableDnsHostNames: true,
        instanceTenancy: 'default',
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

  subnet(name, cidr, availabilityZone, vpc, private=true):: lib.resource('subnet-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'Subnet',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        region: $.region,
        availabilityZone: $.region+availabilityZone,
        cidrBlock: cidr,
        vpcId: vpc.status.atProvider.vpcId,
        mapPublicIPOnLaunch: !private,
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

  eip(name):: lib.resource('eip-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'Address',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        region: $.region,
        domain: 'vpc',
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

  natGateway(name, subnet, eip):: lib.resource('nat-gateway-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'NATGateway',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        region: $.region,
        subnetId: subnet.status.atProvider.subnetId,
        allocationId: eip.status.atProvider.allocationId,
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

  internetGateway(name, vpc):: lib.resource('internet-gateway-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'InternetGateway',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        region: $.region,
        vpcId: vpc.status.atProvider.vpcId,
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

  routeNatGateway(cidr, natGateway):: {
    destinationCidrBlock: cidr,
    natGatewayId: natGateway.status.atProvider.natGatewayId,
  },

  routeGateway(cidr, internetGateway):: {
    destinationCidrBlock: cidr,
    gatewayId: internetGateway.status.atProvider.internetGatewayId,
  },

  routeTable(name, routes, subnets, vpc):: lib.resource('route-table-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'RouteTable',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        region: $.region,
        routes: routes,
        associations: [
          {
            subnetId: subnet.status.atProvider.subnetId,
          }
          for subnet in subnets
        ],
        vpcId: vpc.status.atProvider.vpcId,
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

  securityGroup(
    name,
    vpc,
    ingress=[
      {
        ipProtocol: '-1',
        ipRanges: [
          {
            cidrIp: '0.0.0.0/0',
          },
        ],
      },
    ],
    egress=[
      {
        ipProtocol: '-1',
        ipRanges: [
          {
            cidrIp: '0.0.0.0/0',
          },
        ],
      },
    ]
  ):: lib.resource('security-group-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'SecurityGroup',
    metadata: {
      name: xr.metadata.name+'-'+name,
    },
    spec: {
      forProvider: {
        region: $.region,
        vpcId: vpc.status.atProvider.vpcId,
        groupName: xr.metadata.name+'-'+name,
        ingress: ingress,
        egress: egress,
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
  }
  ),
}