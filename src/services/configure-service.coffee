{Validator} = require 'jsonschema'
_           = require 'lodash'
Encryption  = require 'meshblu-encryption'

debug = require('debug')('slurry-core:configure-service')

MISSING_ROUTE_HEADER = 'Missing x-meshblu-route header in request'

class ConfigureService
  constructor: ({@configureHandler}) ->
    throw new Error 'configureHandler is required' unless @configureHandler?
    @validator = new Validator

  configureSchema: (callback) =>
    @configureHandler.configureSchema callback

  configure: ({auth, slurry, config, route}, callback) =>
    return callback @_userError(MISSING_ROUTE_HEADER, 422) if _.isEmpty route
    firstHop       = _.first JSON.parse route
    userDeviceUuid = firstHop.to
    debug 'save', JSON.stringify({userDeviceUuid, config})

    encryption = Encryption.fromJustGuess auth.privateKey
    encrypted  = encryption.decrypt slurry.encrypted
    auth = _.pick auth, ['uuid', 'token']
    @configureHandler.onConfigure {auth, userDeviceUuid, encrypted, config}, callback

  _userError: (configure, code) =>
    error = new Error configure
    error.code = code if code?
    return error

module.exports = ConfigureService
