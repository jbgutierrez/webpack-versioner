workflow = require './workflow'
path = require 'path'
[_, __main, file, manifest] = process.argv

usage = ->
  basename = path.basename __main
  console.error "usage: #{basename} file.coffee versions.manifest.json"

if file and manifest
  workflow.run file, manifest
else
  usage()
