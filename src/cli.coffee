workflow = require './workflow'
[_, __main, file, manifest] = process.argv

workflow.run file, manifest
