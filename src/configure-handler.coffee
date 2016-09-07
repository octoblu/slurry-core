_    = require 'lodash'
path = require 'path'
glob = require 'glob'

class ConfigureHandler
  constructor: ({ @slurrySpreader, @defaultConfiguration, @configurationsPath }={}) ->
    throw new Error 'ConfigureHandler requires configurationsPath' unless @configurationsPath?
    throw new Error 'ConfigureHandler requires slurrySpreader' unless @slurrySpreader?
    @configurations = @_getConfigurations()
    @_slurries = {}
    @slurrySpreader.on 'create', @_onSlurryCreate
    @slurrySpreader.on 'destroy', @_onSlurryDestroy

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

    @_slurries[uuid]?.destroy()

    return if config.slurry?.disabled
    slurryConfiguration.action {encrypted, auth, userDeviceUuid: uuid}, config, (error, slurryStream) =>
      return console.error error.stack if error?
      @_slurries[uuid] = slurryStream
      @_slurries[uuid].__secretSquirelReconnect = => @_onSlurryCreate slurry
      @_slurries[uuid].on 'end', @_slurries[uuid].__secretSquirelReconnect

  _onSlurryDestroy: (slurry) =>
    {
      uuid
    } = slurry
    @_slurries[uuid]?.removeListener 'end', @_slurries[uuid]?.__secretSquirelReconnect
    @_slurries[uuid]?.destroy()

  formSchema: (callback) =>
    callback null, @_formSchemaFromConfigurations @configurations

  configureSchema: (callback) =>
    callback null, @_configureSchemaFromConfigurations @configurations

  _formSchemaFromConfigurations: (configurations) =>
    return {
      configure: _.mapValues configurations, 'form'
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

  _configureSchemaFromJob: (job, key) =>
    configure = _.cloneDeep job.configure
    _.set configure, 'x-form-schema.angular', "configure.#{key}.angular"
    slurryProp = _.get configure, 'properties.slurry'
    newSlurryProp = _.merge slurryProp, @_generateConfigureSlurry()
    _.set configure, 'properties.slurry', newSlurryProp
    configure.required = _.union ['metadata'], configure.required
    return configure

  _configureSchemaFromConfigurations: (configurations) =>
    _.mapValues configurations, @_configureSchemaFromJob

module.exports = ConfigureHandler
