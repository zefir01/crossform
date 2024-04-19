package test

//_observed:{
//    ggg: {
//        res1: "res1"
//    }
//}
//xr:{
//    spec: inputs:{
//        test1: "aaa"
//    }
//}
//input:{
//    _name: string
//    _crossform:{
//        metadata:{
//            id: _name
//            type: "resource"
//        }
//    }
//    value: xr.spec.inputs[_name]
//}

//#resource: {
//    _id: string
//    _crossform:{
//        metadata:{
//            id: _id
//            type: "resource"
//        }
//    }
//    _observed[_id]
//}



resource1: #resource & {
                        _id: "test-cue-namespace"
                        apiVersion: "kubernetes.crossplane.io/v1alpha2",
                        kind: "Object",
                        metadata: {
                          name: "test-cue-namespace",
                        },
                        spec: {
                          forProvider: {
                            manifest: {
                              apiVersion: "v1",
                              kind: "Namespace",
                              metadata: {
                                labels: {
                                  example: "true",
                                },
                              },
                            },
                          },
                          providerConfigRef: {
                            name: "kubernetes-provider",
                          },
                        },
                      }

resource2: #resource & {
                        _id: "test-cue-namespace2"
                        apiVersion: "kubernetes.crossplane.io/v1alpha2",
                        kind: "Object",
                        metadata: {
                          name: "test-cue-namespace-"+resource1.status.atProvider.manifest.apiVersion
                        },
                        spec: {
                          forProvider: {
                            manifest: {
                              apiVersion: "v1",
                              kind: "Namespace",
                              metadata: {
                                labels: {
                                  example: "true",
                                },
                              },
                            },
                          },
                          providerConfigRef: {
                            name: "kubernetes-provider",
                          },
                        },
                      }
//input: _input & {_name: "test1"}