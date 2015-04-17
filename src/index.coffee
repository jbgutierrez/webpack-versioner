fs     = require 'fs'
path   = require 'path'

parseManifest = (manifestPath) ->
  config = JSON.parse fs.readFileSync manifestPath
  modules = config.modules
  alias = {}
  for moduleName, version of modules
    version = version.replace '=', ''
    modulePath = path.join 'versions', moduleName + '-v.' + version
    console.log modulePath
    alias[moduleName] = modulePath

  version = config['build-info'].$version.split('@')[0]

  version: version
  alias: alias

module.exports =
  parseManifest: parseManifest
