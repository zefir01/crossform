local observed = std.extVar('observed');
local requested = std.extVar('requested');
local input = std.extVar('input');
local xr = std.extVar('xr');

local getCondition(obj, type) =
  local arr = [
    i.status
    for i in obj
    if i.type==type
  ];
  if std.length(arr)==0 then "" else arr[0];

local conditionsTrue(id) =
  local o = std.get(observed, id, {});
    std.objectHas(o, 'status')
    && std.objectHas(o.status, 'conditions')
    && getCondition(o.status.conditions, 'Ready')=='True'
    && getCondition(o.status.conditions, 'Synced')=='True';

local isReady(res) =
  assert std.isObject(res) || std.isArray(res): 'parameter should be one resource or array of resources';
  if std.isArray(res) then
    local m = [
      conditionsTrue(r)
      for r in res
    ];
      std.length(m)==0 || std.all(m)
  else conditionsTrue(res);


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

  resource(id, obj, dependOn=null, ready=null)::
    std.mergePatch(std.get(observed, id, {}), obj)
    +
    {
      assert std.type(id)=='string' : 'id should be string',
      crossform:: {
        metadata: {
          id: id,
          type: 'resource',
        },
        ready: if ready==null then conditionsTrue(id) else ready,
        deferred: if dependOn==null then false else isReady(dependOn),
      },
    },

  input(name, type=null, description=null, default=null, schema=null):: {
    assert (type!='object' && type!='array') || schema!=null: 'You have to define schema for complex types e.g. object, array',
    assert schema==null || (type==null && description==null): 'If you define schema, parameters type and description are not allowed',
    crossform:: {
      metadata: {
        id: name,
        type: 'input',
      },
      [if type!=null || schema!=null then 'schema']: if schema==null then {
        type: type,
        [if default!=null then 'default']: default,
        [if description!=null then 'description']: description,
      } else schema+{
        [if default!=null then 'default']: default,
        [if description!=null then 'description']: description,
      },
    },
    value: if default==null then xr.spec.inputs[name]
    else std.get(xr.spec.inputs, name, default),
  },

  output(id, value):: {
    crossform:: {
      metadata: {
        id: id,
        type: 'output',
      },
      output: value,
    },
  },
}

