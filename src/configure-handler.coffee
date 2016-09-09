_    = require 'lodash'
path = require 'path'
glob = require 'glob'

class ConfigureHandler
  constructor: ({ @slurrySpreader, @defaultConfiguration, @configurationsPath }={}) ->
    throw new Error 'ConfigureHandler requires configurationsPath' unless @configurationsPath?
    throw new Error 'ConfigureHandler requires slurrySpreader' unless @slurrySpreader?
    @configurations = @_getConfigurations()
    @_slurryStreams = {}
    @slurrySpreader.on 'create', @_onSlurryCreate
    @slurrySpreader.on 'destroy', @_onSlurryDestroy

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

  _destroySlurry: (slurry) =>
    { uuid } = slurry
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

    @_destroySlurry slurry
    return if config.slurry?.disabled

    slurryConfiguration.action {encrypted, auth, userDeviceUuid: uuid}, config, (error, slurryStream) =>
      return console.error error.stack if error?

      slurryStream.__slurryOnClose = =>
        @_onSlurryClose slurry

      slurryStream.__slurryOnError = (error) =>
        console.error error.stack
        @_destroySlurry slurry

      throw new Error 'slurryStream must implement on method' unless _.isFunction slurryStream?.on
      slurryStream.on 'close', slurryStream.__slurryOnClose
      slurryStream.on 'error', slurryStream.__slurryOnError
      @_slurryStreams[uuid] = slurryStream

  _onSlurryDestroy: (slurry) =>
    @_destroySlurry slurry

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

module.exports = ConfigureHandler
