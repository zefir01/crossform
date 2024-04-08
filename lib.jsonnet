local observed = std.extVar('observed');
local requested = std.extVar('requested');
local input = std.extVar('input');

local getCondition(obj, type) =
  local arr = [
    i.status
    for i in obj
    if i.type==type
  ];
  if std.length(arr)==0 then "" else arr[0];

{
  request(id, apiVersion, kind, selector):: {
    assert std.type(selector)=='string' || std.type(selector)=='object' : 'request selector should be labels object or string name',
    assert std.type(id)=='string' : 'id should be string',
    crossform:: {
      metadata: {
        id: id,
        type: 'request',
      },
      request: {
        apiVersion: apiVersion,
        kind: kind,
        [if std.type(selector)=='string' then 'name']: selector,
        [if std.type(selector)=='object' then 'labels']: selector,
      },
    },
    result: std.get(requested, id, if std.type(selector)=='string' then {} else []),
  },

  resource(id, obj={})::
    std.mergePatch(std.get(observed, id, {}), obj)
    +
    {
      assert std.type(id)=='string' : 'id should be string',
      crossform:: {
        metadata: {
          id: id,
          type: 'resource',
        },
        local o = std.get(observed, id, {}),
        ready: std.objectHas(o, 'status')
        && std.objectHas(o.status, 'conditions')
        && getCondition(o.status.conditions, 'Ready')=='True'
        && getCondition(o.status.conditions, 'Synced')=='True',
      },
    },
}
