local getSize(maskBits) = std.pow(2, 32-maskBits);

local getNetworkParams(cidr, maskBits) = {
  mask: (std.pow(2, maskBits)-1)<<32-maskBits,
  network: cidr & $.mask,
  host: cidr & ~$.mask,
  size: getSize(maskBits),
  broadcast: $.network+$.size-1,
};

local parseCidr(cidr) = {
  local netStr = std.split(cidr, '/')[0],
  local netInts = [ std.parseInt(i) for i in std.split(netStr, '.')],
  maskBits: std.parseInt(std.split(cidr, '/')[1]),
  addr: (netInts[0] << 24) | (netInts[1] << 16) | (netInts[2] << 8) | (netInts[3] << 0),
};

local getBytes(num) = [(num >> i*8) & std.parseHex('FF') for i in [3, 2, 1, 0]];
local getCidr(num) = std.join('.', [std.toString(i) for i in getBytes(num)]);
local networkParamToStr(params) = {
  mask: getCidr(params.mask),
  network: getCidr(params.network),
  //host: getCidr(params.host),
  size: params.size,
  broadcast: getCidr(params.broadcast),
};

local calcNetworks(cidrStr, nets) =
  local parsed = parseCidr(cidrStr);
  local baseParams = getNetworkParams(parsed.addr, parsed.maskBits);
  local sizes = [getSize(i) for i in nets];

  assert std.sum([baseParams.network]+ sizes) <= baseParams.broadcast+1 : 'Networks out if bound';

  [
    local prev = std.sum([baseParams.network] + std.slice(sizes, 0, i, 1));
    networkParamToStr(getNetworkParams(prev, nets[i]))
    for i in std.range(0, std.length(nets)-1)
  ];

{
//  nets: [25, 25],
//  cidr: '192.168.1.5/24',
//  ttt: calcNetworks($.cidr, $.nets),
  calcNetworks(cidrStr, nets)::
    local parsed = parseCidr(cidrStr);
    local baseParams = getNetworkParams(parsed.addr, parsed.maskBits);
    local sizes = [getSize(i) for i in nets];
    assert std.sum([baseParams.network]+ sizes) <= baseParams.broadcast+1 : 'Networks out if bound';
    [
      local prev = std.sum([baseParams.network] + std.slice(sizes, 0, i, 1));
      networkParamToStr(getNetworkParams(prev, nets[i]))
      for i in std.range(0, std.length(nets)-1)
    ],
}
