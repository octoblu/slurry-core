_           = require 'lodash'
path        = require 'path'
glob        = require 'glob'
MeshbluHTTP = require 'meshblu-http'
moment      = require 'moment'
debug       = require('debug')('slurry-core:configure-handler')

THIRTY_SECONDS = 30 * 1000

class ConfigureHandler
  constructor: ({ @slurrySpreader, @defaultConfiguration, @configurationsPath, @meshbluConfig }={}) ->
    throw new Error 'ConfigureHandler requires configurationsPath' unless @configurationsPath?
    throw new Error 'ConfigureHandler requires slurrySpreader' unless @slurrySpreader?
    @configurations = @_getConfigurations()
    @_slurryStreams = {}
    @slurrySpreader.on 'create', @_onSlurryCreate
    @slurrySpreader.on 'destroy', @_onSlurryDestroy
    @slurrySpreader.on 'onlineUntil', @_updateOnlineUntil

  configureSchema: (callback) =>
    callback null, @_configureSchemaFromConfigurations @configurations

  formSchema: (callback) =>
    callback null, @_formSchemaFromConfigurations @configurations

  onConfigure: ({auth, userDeviceUuid, encrypted, config}, callback) =>
    selectedConfiguration = config.schemas?.selected?.configure ? @defaultConfiguration ? 'Default'
    slurry = {
      auth
      selectedConfiguration
      encrypted
      config
      uuid: userDeviceUuid
    }
    return @slurrySpreader.remove(slurry, callback) if config.slurry?.disabled
    @slurrySpreader.add slurry, callback

  _configureSchemaFromConfigurations: (configurations) =>
    _.mapValues configurations, @_configureSchemaFromJob

  _configureSchemaFromJob: (job, key) =>
    configure = _.cloneDeep job.configure
    _.set configure, 'x-form-schema.angular', "configure.#{key}.angular"
    slurryProp = _.get configure, 'properties.slurry'
    newSlurryProp = _.merge slurryProp, @_generateConfigureSlurry()
    _.set configure, 'properties.slurry', newSlurryProp
    configure.required = _.union ['metadata'], configure.required
    return configure

  _destroySlurry: ({ uuid }) =>
    slurryStream = @_slurryStreams[uuid]
    return unless slurryStream?
    slurryStream.removeListener 'close', slurryStream.__slurryOnClose
    slurryStream.removeListener 'error', slurryStream.__slurryOnError
    delete slurryStream.__slurryOnClose
    throw new Error 'slurryStream must implement destroy method' unless _.isFunction slurryStream?.destroy
    slurryStream.destroy()
    delete @_slurryStreams[uuid]

  _onSlurryCreate: (slurry) =>
    {
      uuid
      selectedConfiguration
      config
      encrypted
      auth
    } = slurry
    slurryConfiguration = @configurations[selectedConfiguration]
    return unless slurryConfiguration?

    @_destroySlurry { uuid }
    return if config.slurry?.disabled

    slurryConfiguration.action {encrypted, auth, userDeviceUuid: uuid}, config, (error, slurryStream) =>
      @_updateStatusDeviceWithError {auth, userDeviceUuid: uuid, error} if error?

      if error?
        console.error error.stack
        @slurrySpreader.delay {uuid, timeout:THIRTY_SECONDS}, _.noop if error.code == 401
        @slurrySpreader.close {uuid}, _.noop
        return

      return @_onSlurryDelay slurry unless slurryStream?

      slurryStream.__slurryOnClose = =>
        @_onSlurryClose slurry

      slurryStream.__slurryOnError = (error) =>
        console.error error.stack
        @_updateStatusDeviceWithError {auth, userDeviceUuid: uuid, error}
        @_destroySlurry slurry

      slurryStream.__slurryOnDelay = (error, timeout=THIRTY_SECONDS) =>
        throw new Error 'parameter "error" must pass _.isError' unless _.isError error
        console.error error.stack
        @_updateStatusDeviceWithError {auth, userDeviceUuid: uuid, error}
        @_onSlurryDelay {uuid, timeout}

      throw new Error 'slurryStream must implement on method' unless _.isFunction slurryStream?.on
      slurryStream.on 'close', slurryStream.__slurryOnClose
      slurryStream.on 'error', slurryStream.__slurryOnError
      slurryStream.on 'delay', slurryStream.__slurryOnDelay
      @_slurryStreams[uuid] = slurryStream

  _onSlurryDelay: ({uuid, timeout}) =>
    @_destroySlurry { uuid }
    @slurrySpreader.delay {uuid, timeout}, (error) =>
      @_slurryStreams[uuid].destroy?()
      return console.error error if error?

  _onSlurryDestroy: ({ uuid }) =>
    @_destroySlurry { uuid }

  _onSlurryClose: (slurry) =>
    @slurrySpreader.close slurry, _.noop

  _formSchemaFromConfigurations: (configurations) =>
    return {
      configure: _.mapValues configurations, 'form'
    }

  _generateConfigureSlurry: =>
    return {
      type: 'object'
      required: ['disabled']
      properties:
        disabled:
          type: 'boolean'
          title: 'Disabled'
          description: 'Disable streaming'
    }

  _getConfigurations: =>
    dirnames = glob.sync path.join(@configurationsPath, '/*/')
    configurations = {}
    _.each dirnames, (dir) =>
      key = _.upperFirst _.camelCase path.basename dir
      try
        configurations[key] = require dir
      catch error
        console.error error.stack

    return configurations

  _updateOnlineUntil: ({slurry, onlineUntil}) =>
    {auth, config} = slurry
    {statusDevice} = config
    @_addStatusDeviceRef {auth, statusDevice} unless @_hasStatusDeviceRef config
    meshblu = new MeshbluHTTP _.defaults auth, @meshbluConfig
    meshblu.update statusDevice, {
      'status.onlineUntil': onlineUntil
    }, (error) => console.error error.stack if error?

  _hasStatusDeviceRef: (config) =>
    return config?.status?.$ref?

  _addStatusDeviceRef: ({auth, statusDevice}) =>
    meshblu = new MeshbluHTTP _.defaults auth, @meshbluConfig
    meshblu.update auth.uuid, {
      status: $ref: "meshbludevice://#{statusDevice}/#/status"
    }, (error) => console.error error.stack if error?

  _updateStatusDeviceWithError: ({auth, userDeviceUuid, error}, callback=_.noop) =>
    debug '_updateStatusDeviceWithError', userDeviceUuid, error

    meshblu = new MeshbluHTTP _.defaults auth, @meshbluConfig
    meshblu.device userDeviceUuid, (newError, {statusDevice}={}) =>
      debug '_updateStatusDeviceWithError:statusDevice', newError?.message, statusDevice
      return callback newError if newError?
      return callback() unless statusDevice?
      update =
        $push:
          errors:
            $each: [
              date: moment.utc().format()
              code: error.code ? 500
              message: error.message
            ]
            $slice: -99
      meshblu.updateDangerously statusDevice, update, callback

module.exports = ConfigureHandler
