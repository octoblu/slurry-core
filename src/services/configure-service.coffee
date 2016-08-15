{Validator} = require 'jsonschema'
_           = require 'lodash'
Encryption  = require 'meshblu-encryption'
MeshbluHTTP = require 'meshblu-http'

debug = require('debug')('slurry-core:configure-service')

MISSING_METADATA     = 'Message is missing required property "metadata"'
MISSING_ROUTE_HEADER = 'Missing x-meshblu-route header in request'

class ConfigureService
  constructor: ({@configureHandler}) ->
    throw new Error 'configureHandler is required' unless @configureHandler?
    @validator = new Validator

  configureSchema: (callback) =>
    @configureHandler.configureSchema callback

  reply: ({auth, route, response, respondTo}, callback) =>
    return callback @_userError(MISSING_ROUTE_HEADER, 422) if _.isEmpty route

    firstHop       = _.first JSON.parse route
    senderUuid     = firstHop.from
    userDeviceUuid = firstHop.to
    metadata       = _.assign {to: respondTo}, response.metadata

    configure =
      devices:  [senderUuid]
      metadata: metadata
      data:     response.data

    meshblu = new MeshbluHTTP auth
    meshblu.message configure, as: userDeviceUuid, callback

  replyWithError: ({auth, error, route, respondTo}, callback) =>
    return callback @_userError(MISSING_ROUTE_HEADER, 422) if _.isEmpty route
    firstHop       = _.first JSON.parse route
    senderUuid     = firstHop.from
    userDeviceUuid = firstHop.to

    configure =
      devices: [senderUuid]
      metadata:
        code: error.code ? 500
        to: respondTo
        error:
          configure: error.configure

    meshblu = new MeshbluHTTP auth
    meshblu.message configure, as: userDeviceUuid, callback

  send: ({auth, slurry, configure}, callback) =>
    return callback @_userError(MISSING_METADATA, 422) unless configure?.metadata?
    {data, metadata} = configure
    debug 'send', JSON.stringify({data,metadata})

    encryption = Encryption.fromJustGuess auth.privateKey
    encrypted  = encryption.decrypt slurry.encrypted
    @configureHandler.onMessage {data, encrypted, metadata}, callback

  _userError: (configure, code) =>
    error = new Error configure
    error.code = code if code?
    return error

module.exports = ConfigureService
