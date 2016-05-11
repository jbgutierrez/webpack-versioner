fs             = require 'fs'
path           = require 'path'
parser         = require 'cron-parser'
md5            = require 'md5'
webpack        = require 'webpack'
pathIsAbsolute = require 'path-is-absolute'
pathParse      = require 'path-parse'

DEBUG = process.env.DEBUG
debug = (msg) ->
  console.log "DEBUG: #{msg}"

USER = process.env.USER or process.env.USERNAME
NOW = new Date().toISOString()

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

    debug "last rsync took place at #{@releasedAt}"

class Version
  constructor: (@file) ->
    @author = USER
    @updated = NOW
    [@number, @lastHash, @lastUpdated] = ManifestFile.info @file

    @file.annotate()
    @hash = (md5 @file.contents).substring 0, 6

    @frozed = not @number
    @changed = @lastHash isnt @hash

  update: ->
    if @lastHash and @lastUpdated < VersionScheduler.releasedAt
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
    if ManifestFile.instance.dir isnt @dir
      namespace = path.relative ManifestFile.instance.dir, @dir
      @dir = ManifestFile.instance.dir
      @name = [ namespace, @name ].join '/'

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
    return if /=/.test modules[module.name]?.version
    modules[module.name] =
      version: module.version.version
      author: USER
      updated: NOW

    @version = new Version this
    @contents = JSON.stringify @json, null, '  '

    @version.update()
    @annotate()
    @save()
    debug "touching #{@base}"

  @info: (file) ->
    info = if file is @instance then @instance.json['build-info'] else @instance.json.modules[file.name] || {}
    version = info.version || info.$version
    updated =  new Date info.$updated || info.updated

    if /^(\d+\.\d+)@?(.*)$/.test version
      [RegExp.$1, RegExp.$2, updated]
    else if version
      [false, false, updated]
    else
      number = "1.0"
      [number, false, updated]

module.exports =
  run: (file, manifest) ->
    manifest = ManifestFile.load manifest
    VersionScheduler.setup manifest.json['release-schedules']

    module = new SourceFile file
    if module.touch()
      manifest.touch module
