#!/usr/bin/env coffee
os = require 'os'
fs = require 'fs'
chokidar = require 'chokidar'
spawn = require('child_process').spawn
watcher = null

win32 = ~['win32', 'win64'].indexOf os.platform()
descriptor = (process.env.USER or process.env.USERNAME) + '.watching'

debounce = (fn, delay=2000) ->
  timer = null
  ->
    context = this
    args = arguments
    clearTimeout timer
    timer = setTimeout((->
      fn.apply context, args
    ), delay)

restart = (path) ->
  return if path isnt descriptor
  if watcher
    console.log "firing #{descriptor}"
    watcher.kill()
  else
    fs.writeFileSync descriptor, +new Date unless fs.existsSync descriptor

  cmd = 'webpack'
  cmd += '.cmd' if win32
  watcher = spawn cmd, ['--watch', '--watch-polling'], stdio: 'inherit'
  console.log "starting #{descriptor}"

touch =
  debounce ->
    entries = fs.readdirSync '.'
    for entry in entries when /\.watching/.test entry
      continue if entry is descriptor
      console.log "restarting #{entry}"
      fs.writeFileSync entry, +new Date

    restart descriptor

exit = (path) ->
  return if path and path isnt descriptor
  watcher.kill()
  watcher1.close()
  watcher2.close()
  if fs.existsSync descriptor
    fs.unlinkSync descriptor
    console.log "removing #{descriptor}"
  else
    console.log "exiting #{descriptor} after remote removal"

  process.exit()

options =
  usePolling: true
  interval: 100

options = {} if win32

watcher1 = chokidar.watch('modules/versions', options).on 'add', touch
watcher2 = chokidar.watch('*.watching', options).on('change', restart).on('unlink', exit)

process.on 'SIGINT', exit
