local repo_url = std.extVar('repo_url');
local revision = std.extVar('revision');

[
//  {
//    apiVersion: 'crossform.io/v1alpha1',
//    kind: 'xModule',
//    metadata: {
//      name: 'test1',
//    },
//    spec: {
//      repository: repo_url,
//      revision: revision,
//      path: 'examples/test2',
//      inputs: {
//        test1: 'aaa',
//      },
//    },
//  },

  {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: {
      name: 'testttt',
    },
  }
]