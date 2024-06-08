local lib = std.extVar('crossform');

{
  providerConfig: null,
  withProviderConfig(name):: ${ providerConfig: name },
  region: 'us-east-1',
  withRegion(region):: ${ region: region },

  vpc(name, cidr):: lib.resource('vpc-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'VPC',
    metadata: {
      name: name,
    },
    spec: {
      forProvider: {
        region: $.region,
        cidrBlock: cidr,
        enableDnsSupport: true,
        enableDnsHostNames: true,
        instanceTenancy: 'default',
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  subnet(name, cidr, availabilityZone, vpc):: lib.resource('subnet-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'Subnet',
    metadata: {
      name: name,
    },
    spec: {
      forProvider: {
        region: $.region,
        availabilityZone: $.region+availabilityZone,
        cidrBlock: cidr,
        vpcId: vpc.status.atProvider.vpcId,
        mapPublicIPOnLaunch: true,
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),

  natGateway(name):: lib.resource('nat-gateway-'+name, {
    apiVersion: 'ec2.aws.crossplane.io/v1beta1',
    kind: 'NATGateway',
    metadata: {
      name: name,
    },
    spec: {
      forProvider: {
        region: $.region,
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
      name: name,
    },
    spec: {
      forProvider: {
        region: $.region,
        vpcId: vpc.status.atProvider.vpcId,
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
      name: name,
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
      },
      [if $.providerConfig!=null then 'providerConfigRef']: {
        name: $.providerConfig,
      },
    },
  }),
}