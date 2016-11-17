{Validator} = require 'jsonschema'
_           = require 'lodash'
Encryption  = require 'meshblu-encryption'
moment      = require 'moment'
MeshbluHTTP = require 'meshblu-http'

debug = require('debug')('slurry-core:configure-service')

MISSING_ROUTE_HEADER = 'Missing x-meshblu-route header in request'

class ConfigureService
  constructor: ({@configureHandler, @meshbluConfig}) ->
    throw new Error 'configureHandler is required' unless @configureHandler?
    @validator = new Validator

  configureSchema: (callback) =>
    @configureHandler.configureSchema callback

  formSchema: (callback) =>
    @configureHandler.formSchema callback

  configure: ({auth, slurry, config, route}, callback) =>
    return callback @_userError(MISSING_ROUTE_HEADER, 422) if _.isEmpty route
    firstHop       = _.first JSON.parse route
    userDeviceUuid = firstHop.from
    debug 'save', JSON.stringify({userDeviceUuid, config})

    encryption = Encryption.fromJustGuess auth.privateKey
    encrypted  = encryption.decrypt slurry.encrypted
    meshbluHttp = new MeshbluHTTP _.defaults auth, @meshbluConfig
    meshbluHttp.generateAndStoreToken auth.uuid, (error, auth) =>
      return callback error if error?
      @configureHandler.onConfigure {auth, userDeviceUuid, encrypted, config}, (newError) =>
        return callback newError if newError?
        @_updateStatusDeviceWithError {auth, userDeviceUuid, error}, callback

  _updateStatusDeviceWithError: ({auth, userDeviceUuid, error}, callback) =>
    meshblu = new MeshbluHTTP _.defaults auth, @meshbluConfig
    meshblu.device userDeviceUuid, (newError, {statusDevice}={}) =>
      return callback() if newError?
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
      meshblu.updateDangerously statusDevice, update, as: userDeviceUuid, callback

  _userError: (configure, code) =>
    error = new Error configure
    error.code = code if code?
    return error

module.exports = ConfigureService
