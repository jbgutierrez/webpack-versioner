path = require 'path'
[_, __main, option1, option2] = process.argv

usage = ->
  basename = path.basename __main
  console.error """
usage: #{basename} <option>
options:
  module_path project_root  - Handles module versioning
  -w, --watch               - Hires/fires webpack watcher upon versioning changes
"""

switch
  when /-w|--watch/.test option1
    require './watcher'
  when option1 and option2
    [file, GLOBAL.PROJECT_ROOT] = [option1, option2]
    require('./workflow').run file
  else
    usage()
