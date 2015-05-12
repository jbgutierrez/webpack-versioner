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
    [@number, @lastHash] = ManifestFile.info @file

    @file.annotate()
    @hash = (md5 @file.contents).substring 0, 6

    @frozed = not @number
    @changed = @lastHash isnt @hash or DEBUG

  update: ->
    if @lastHash and ManifestFile.lastUpdated < VersionScheduler.releasedAt
      @increment()
      debug "will save new version #{@number} of #{@file.base}"

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

    @version = {}

  save: (fullpath=@fullpath) ->
    fs.writeFileSync fullpath, @contents

  annotate: ->
    anotations = [ 'author', 'updated', 'version' ].join('|')
    re = new RegExp "(\")?\\$(#{anotations})\\1: ?\\1.*\\1", "g"
    @contents = @contents.replace re, (_, quote, annotation) =>
      quote = quote or ''
      "#{quote}$#{annotation}#{quote}: #{quote}#{@version[annotation]}#{quote}"

class SourceFile extends File
  constructor: (p) ->
    super p

  touch: ->
    @version = new Version this
    switch
      when @version.frozed
        debug "current version of #{@base} is frozen"
      when @version.changed
        @version.update()
        @annotate()
        @save()
        @save @version.fullpath()
        debug "touching #{@base}"
        true
      else
        debug "current version of #{@base} is up to date"

class ManifestFile extends File
  @load: (p) -> @instance = new ManifestFile p
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

  touch: (module) ->
    modules = @json.modules
    return if /=/.test modules[module.name]
    modules[module.name] = module.version.version

    @version = new Version this
    @contents = JSON.stringify @json, null, '  '

    @version.update()
    @annotate()
    @save()
    debug "touching #{@base}"

  @info: (file) ->
    version = if file is @instance
      @instance.json['build-info'].$version
    else
      @instance.json.modules[file.name]

    if /^(\d+\.\d+)@?(.*)$/.test version
      [RegExp.$1, RegExp.$2]
    else if version
      [false, false]
    else
      /\$version: (\d+\.\d+)/.test file.contents
      number = RegExp.$1 or "1.0"
      [number, false]

module.exports =
  run: (file, manifest) ->
    manifest = ManifestFile.load manifest
    VersionScheduler.setup manifest.json['release-schedules']

    module = new SourceFile file
    if module.touch()
      manifest.touch module
