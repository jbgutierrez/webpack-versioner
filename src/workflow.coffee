fs             = require 'fs'
path           = require 'path'
parser         = require 'cron-parser'
md5            = require 'md5'
webpack        = require 'webpack'
pathIsAbsolute = require 'path-is-absolute'
pathParse      = require 'path-parse'

DEBUG = false
debug = (msg) ->
  console.log "DEBUG: #{msg}"

class VersionScheduler
  @setup: (expressions) ->
    now = new Date
    HOURS = 60 * 60 * 1000
    @releasedAt = new Date +now - HOURS * 24

    options =
      currentDate: @releasedAt
      endDate: now

    for expression in expressions
      interval = parser.parseExpression expression, options
      try
        while true
          sync = interval.next()
          @releasedAt = sync if sync > @releasedAt
      catch

    @releasedAt = now if DEBUG

    debug "last rsync took place at #{@releasedAt}"

class Version
  constructor: (@file) ->
    @author = process.env.USER or process.env.USERNAME
    @updated = new Date().toISOString()

    error = """
      Please make sure your file '#{@file.fullpath}' has the following `magic comments`:

        // $version: 1.0
        // $author:
        // $updated:

      """

    if /("?)\$updated\1: ?\1(.*)\1/.test @file.contents
      @lastUpdated = if RegExp.$2 then new Date RegExp.$2 else new Date
    else
      throw error

    if /("?)\$version\1: \1(\d+\.\d+)@?(.*)\1/.test @file.contents
      [@number, @lastHash] = [RegExp.$2, RegExp.$3]
    else
      throw error

    version = "#{@number}@#{@lastHash}"
    @file.contents = @file.
      contents.
      replace(version, @number).
      replace(@lastUpdated.toISOString(), '')
    @hash = md5(@file.contents).substring 0, 6

    @changed = @lastHash isnt @hash or DEBUG

  update: ->
    if @lastUpdated < VersionScheduler.releasedAt
      @increment()
      debug "saving version #{@number} of #{@file.base}"

    @version = "#{@number}@#{@hash}"

  increment: ->
    /(\d+).(\d+)/.test @number
    [major, minor] = [RegExp.$1, RegExp.$2]
    number = (+major * 10000) + +minor
    major = Math.floor number / 10000
    minor = number % 10000 + 1
    @number = "#{major}.#{minor}"

  filename: -> "#{@file.name}-v.#{@number}#{@file.ext}"
  fullpath: -> [@file.dir, 'versions', @filename()].join path.sep

class File
  constructor: (p) ->
    fullpath = if pathIsAbsolute p then p else [process.cwd(), p].join path.sep
    @fullpath = path.normalize fullpath
    this[key] = value for key, value of pathParse @fullpath
    @contents = fs.readFileSync(@fullpath).toString() if fs.existsSync @fullpath
    @version = new Version this

  versionate: (saveCopy=true)->

    if @version.changed
      @annotate()
      @save()
      @save @version.fullpath() if saveCopy
      true
    else
      debug "current and previous versions of #{@base} are identical"

  save: (fullpath=@fullpath) ->
    fs.writeFileSync fullpath, @contents

  annotate: ->
    @version.update()
    anotations = [ 'author', 'updated', 'version' ].join('|')
    re = new RegExp "(\")?\\$(#{anotations})\\1: \\1.*\\1", "g"
    @contents = @contents.replace re, (_, quote, annotation) =>
      quote = quote or ''
      "#{quote}$#{annotation}#{quote}: #{quote}#{@version[annotation]}#{quote}"

class ManifestFile extends File
  constructor: (p) ->
    error = """
      Please create the manifest file at '#{p}':

      {
        "build-info": {
          "$updated": "",
          "$version": "1.0"
        },
        "release-schedules": ["0 0 * * *"],
        "modules": {}
      }

      """
    throw error unless fs.existsSync p
    super p
    @json = JSON.parse @contents

  versionate: (module) ->
    modules = @json.modules
    re = new RegExp "=|#{module.version}"
    return if modules[module.name] and re.test modules[module.name]
    modules[module.name] = module.version.number

    @contents = JSON.stringify @json, null, '  '

    super false

module.exports =
  run: (file, dir) ->
    manifest = new ManifestFile [dir, 'versions.manifest.json'].join path.sep
    VersionScheduler.setup manifest.json['release-schedules']

    module = new File file
    if module.versionate()
      manifest.versionate(module)
      debug "bundling version #{manifest.version.number}"
      dir = if pathIsAbsolute dir then dir else [process.cwd(), dir].join path.sep
      config = require [dir, 'webpack.config.js'].join path.sep
      webpack config, (err, stats) ->
        if err
          console.error err.stack || err
          console.error err.details if err.details
        else
          manifest.versionate(module)
