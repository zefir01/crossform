local repo_url = std.extVar('repo_url');
local revision = std.extVar('revision');

[
  {
    apiVersion: 'crossform.io/v1alpha1',
    kind: 'xModule',
    metadata: {
      name: 'test1',
    },
    spec: {
      repository: 'git@github.com:zefir01/test2.git',
      revision: 'main',
      path: 'project1',
    },
  }
]