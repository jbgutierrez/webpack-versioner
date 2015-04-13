workflow = require './workflow'
[_, __main, file, dir] = process.argv

workflow.run file, dir
