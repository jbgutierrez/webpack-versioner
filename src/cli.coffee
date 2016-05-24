path = require 'path'
[_, __main, arg] = process.argv

usage = ->
  basename = path.basename __main
  console.error """
usage: #{basename} <option>
options:
   module_path  - Handles module versioning
  -w, --watch   - Hires/fires webpack watcher upon versioning changes
"""

switch
  when /-w|--watch/.test arg
    require './watcher'
  when arg
    require('./workflow').run arg
  else
    usage()
