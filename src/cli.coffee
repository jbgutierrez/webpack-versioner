path = require 'path'
[_, __main, option1, option2] = process.argv

usage = ->
  basename = path.basename __main
  console.error """
usage: #{basename} <option>
options:
   modules/module_name versions.manifest.json - Handles module versioning
  #{basename} -w, --watch                     - Hires/fires webpack watcher upon versioning changes
"""

switch
  when /-w|--watch/.test option1
    require './watcher'
  when option1 and option2
    [file, manifest] = [option1, option2]
    require('./workflow').run file, manifest
  else
    usage()
