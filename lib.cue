//_observed:{}
//_requested:{}
//_xr:{}
//_context:{}


#request:{
  _id: string
  _apiVersion: string
  _kind: string
  _name?: string
  _labels?: [string]:string
  _crossform:{
    metadata:{
        id: _id
        type: "request"
    }
    request: {
      apiVersion: _apiVersion,
      kind: _kind,
      if _name!=null{
          name: _name
      }
      if _labels!=null{
        labels: _labels
      }
    }
  }
  result: _requested[_id] | null
}

#input:{
  _name: string
  _crossform:{
    metadata:{
        id: _name
        type: "input"
    }
  }
  value: _xr.spec.inputs[_name]
}
#resource: {
  _id: string
  _deferred: bool | *false | _
  _crossform:{
    metadata:{
      id: _id
      type: "resource"
    }
    ready: len([ for _, n in *_observed[_id].status.conditions | {} if (n.type == "Ready" || n.type == "Synced") && n.status=="True" {}])==2
    deferred: _deferred
  }
  *_observed[_id] | {}
  ...
}

#output: {
  _id: string
  _value: _
  _crossform: {
    metadata: {
      id: id,
      type: "output",
    },
    output: _value,
  },
}