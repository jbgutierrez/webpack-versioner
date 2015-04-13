fs   = require 'fs'
path = require 'path'

module.exports = (dirname) ->
  manifest = [dirname, 'versions.manifest.json'].join path.sep
  config = JSON.parse fs.readFileSync manifest
  modules = config.modules
  alias = {}
  for moduleName, moduleVersion of modules
    moduleVersion = moduleVersion.replace('=', '')
    alias[moduleName] = path.join dirname, 'modules/versions/' + moduleName + '-v.' + moduleVersion

  moduleVersion = config['build-info'].$version.split('@')[0]

  version: moduleVersion
  alias: alias
