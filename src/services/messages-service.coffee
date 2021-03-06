{Validator} = require 'jsonschema'
_           = require 'lodash'
Encryption  = require 'meshblu-encryption'
MeshbluHTTP = require 'meshblu-http'
moment      = require 'moment'

debug = require('debug')('slurry-core:messages-service')

MISSING_METADATA     = 'Message is missing required property "metadata"'
MISSING_ROUTE_HEADER = 'Missing x-meshblu-route header in request'

class MessagesService
  constructor: ({@messageHandler, @meshbluConfig}) ->
    throw new Error 'messageHandler is required' unless @messageHandler?
    @validator = new Validator

  formSchema: (callback) =>
    @messageHandler.formSchema callback

  messageSchema: (callback) =>
    @messageHandler.messageSchema callback

  reply: ({auth, route, response, respondTo}, callback) =>
    return callback @_userError(MISSING_ROUTE_HEADER, 422) if _.isEmpty route

    firstHop       = _.first JSON.parse route
    senderUuid     = firstHop.from
    userDeviceUuid = firstHop.to
    metadata       = _.assign {to: respondTo}, response.metadata

    message =
      devices:  [senderUuid]
      metadata: metadata
      data:     response.data

    meshblu = new MeshbluHTTP _.defaults auth, @meshbluConfig
    meshblu.message message, as: userDeviceUuid, callback

  replyWithError: ({auth, error, route, respondTo}, callback) =>
    return callback @_userError(MISSING_ROUTE_HEADER, 422) if _.isEmpty route
    firstHop       = _.first JSON.parse route
    senderUuid     = firstHop.from
    userDeviceUuid = firstHop.to

    message =
      devices: [senderUuid]
      metadata:
        code: error.code ? 500
        to: respondTo
        error:
          message: error.message

    meshblu = new MeshbluHTTP _.defaults auth, @meshbluConfig
    meshblu.message message, as: userDeviceUuid, (newError) =>
      return callback newError if newError?
      @_updateStatusDeviceWithError {auth, senderUuid, userDeviceUuid, error, respondTo}, callback

  _updateStatusDeviceWithError: ({auth, senderUuid, userDeviceUuid, error, respondTo}, callback) =>
    meshblu = new MeshbluHTTP _.defaults auth, @meshbluConfig
    meshblu.device userDeviceUuid, (newError, {statusDevice}={}) =>
      return callback() if newError?
      return callback() unless statusDevice?
      update =
        $push:
          'status.errors':
            $each: [
              senderUuid: senderUuid
              date: moment.utc().format()
              metadata:
                to: respondTo
              code: error.code ? 500
              message: error.message
            ]
            $slice: -99
      meshblu.updateDangerously statusDevice, update, as: userDeviceUuid, callback

  responseSchema: (callback) =>
    @messageHandler.responseSchema callback

  send: ({auth, slurry, message}, callback) =>
    return callback @_userError(MISSING_METADATA, 422) unless message?.metadata?
    {data, metadata} = message
    debug 'send', JSON.stringify({data,metadata})

    encryption = Encryption.fromJustGuess auth.privateKey
    encrypted  = encryption.decrypt slurry.encrypted
    @messageHandler.onMessage {data, encrypted, metadata}, callback

  _userError: (message, code) =>
    error = new Error message
    error.code = code if code?
    return error

module.exports = MessagesService
