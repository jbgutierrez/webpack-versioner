fs             = require 'fs'
path           = require 'path'
parser         = require 'cron-parser'
md5            = require 'md5'
webpack        = require 'webpack'
pathIsAbsolute = require 'path-is-absolute'
pathParse      = require 'path-parse'
mkdirp         = require 'mkdirp'

DEBUG = process.env.DEBUG

info = (args...) ->
  console.log "INFO:", args...

debug = (args...) ->
  console.log "DEBUG:", args... if DEBUG

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

    info "last rsync took place at #{@releasedAt}"

class Version
  constructor: (@file) ->
    @author = USER
    @updated = NOW

    if @versionable = ManifestFile.versionable @file
      [@number, @lastHash, @lastUpdated] = ManifestFile.info @file
      debug "*->", [@number, @lastHash, @lastUpdated]
    else
      @version = "0.0"

    @file.annotate()
    @hash = (md5 @file.contents).substring 0, 6

    @frozen = @versionable and not @number
    @changed = @lastHash isnt @hash

  update: ->
    if @lastHash and @lastUpdated < VersionScheduler.releasedAt
      @increment()
      info "will save new version #{@number} of #{@file.base}"

    @version = "#{@number}@#{@hash}"

  increment: ->
    /(\d+).(\d+)/.test @number
    [major, minor] = [RegExp.$1, RegExp.$2]
    number = (+major * 10000) + +minor
    major = Math.floor number / 10000
    minor = number % 10000 + 1
    @number = "#{major}.#{minor}"

  fullpath: ->
    namespace = path.relative PROJECT_ROOT, @file.dir
    mkdirp.sync dir = [PROJECT_ROOT, 'versions', namespace].join path.sep
    filename = "#{@file.name}-v.#{@number}#{@file.ext}"
    [ dir, filename ].join path.sep

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
  touch: ->
    @version = new Version this
    switch
      when @version.frozen
        info "current version of #{@base} is frozen"
      when @version.changed
        @version.update()
        @annotate()
        @save()
        @save @version.fullpath() if @version.versionable
        info "touching #{@base}"
        true
      else
        info "current version of #{@base} is up to date"

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
    return if /=/.test modules[module.base]?.version
    modules[module.base] =
      version: module.version.version
      author: USER
      updated: NOW

    @version = new Version this
    @contents = JSON.stringify @json, null, '  '

    @version.update()
    @annotate()
    @save()
    info "touching #{@base}"

  @info: (file) ->
    meta = if file is @instance then @instance.json['build-info'] else @instance.json.modules[file.base] || {}
    version = meta.version || meta.$version
    updated =  new Date meta.$updated || meta.updated

    if /^(\d+\.\d+)@?(.*)$/.test version
      [RegExp.$1, RegExp.$2, updated]
    else if version
      [false, false, updated]
    else
      number = "1.0"
      [number, false, updated]

  @versionable: (file) ->
    return true if file is @instance
    versionable = @instance.json['versionable-regex']
    not versionable or new RegExp(versionable).test file.fullpath

module.exports =
  run: (file) ->
    dir = pathParse(file).dir
    manifest = ManifestFile.load [PROJECT_ROOT, 'versions.manifest.json'].join path.sep
    VersionScheduler.setup manifest.json['release-schedules']

    module = new SourceFile file
    if module.touch()
      manifest.touch module
