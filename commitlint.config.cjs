const scopes = [
  'beariscope',
  'bearimetric',
  'core',
  'services',
  'ui',
  'honeycomb',
  'repo',
  'workspace',
  'ci',
  'release',
  'deps',
  'docs',
];

module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-empty': [2, 'never'],
    'scope-enum': [2, 'always', scopes],
  },
};
