_ = require 'lodash'
MeshbluHTTP = require 'meshblu-http'
CredentialsDevice = require '../models/credentials-device'
credentialsDeviceCreateGenerator = require '../config-generators/credentials-device-create-config-generator'
Encryption = require 'meshblu-encryption'

class CredentialsDeviceService
  constructor: ({@deviceType, @imageUrl, @meshbluConfig, @serviceUrl}) ->
    throw new Error('deviceType is required') unless @deviceType?
    @uuid = @meshbluConfig.uuid
    @meshblu = new MeshbluHTTP @meshbluConfig
    @encryption = Encryption.fromJustGuess @meshbluConfig.privateKey

  authorizedFind: ({authorizedUuid, credentialsDeviceUuid}, callback) =>
    authorizedKey = @encryption.sign(authorizedUuid)
    @meshblu.search {uuid: credentialsDeviceUuid, 'slurry.authorizedKey': authorizedKey}, {}, (error, devices) =>
      return callback(error) if error?
      device = _.first devices

      return callback @_userError('credentials device not found', 404) unless device?.slurry?.encrypted?
      return callback @_userError('credentials device not found', 404) unless @_isSignedCorrectly device

      options =
        uuid: credentialsDeviceUuid
        encrypted: device.slurry.encrypted

      return @_getCredentialsDevice options, callback

  getSlurryByUuid: (uuid, callback) =>
    @meshblu.device uuid, (error, device) =>
      return callback error if error?
      return callback @_userError 'invalid credentials device', 400 unless @_isSignedCorrectly device
      return callback null, device.slurry

  findOrCreate: (resourceOwnerID, callback) =>
    @_findOrCreate resourceOwnerID, (error, device) =>
      return callback error if error?
      @_getCredentialsDevice device, callback

  _findOrCreate: (resourceOwnerID, callback) =>
    return callback new Error('resourceOwnerID is required') unless resourceOwnerID?
    idKey = @encryption.sign(resourceOwnerID)

    @meshblu.search 'slurry.idKey': idKey, {}, (error, devices) =>
      return callback error if error?
      devices = _.filter devices, @_isSignedCorrectly
      return callback null, _.first devices unless _.isEmpty devices
      record = credentialsDeviceCreateGenerator {serviceUuid: @uuid}
      @meshblu.register record, callback

  _getCredentialsDevice: ({uuid, encrypted}, callback) =>
    @meshblu.generateAndStoreToken uuid, (error, {token}={}) =>
      return callback new Error("Failed to access credentials device") if error?
      meshbluConfig = _.defaults {uuid, token}, @meshbluConfig
      serviceUuid = @uuid
      return callback null, new CredentialsDevice {
        @deviceType
        @imageUrl
        meshbluConfig
        encrypted
        @serviceUrl
        serviceUuid
      }

  _isSignedCorrectly: ({slurry, slurrySignature, uuid}={}) =>
    return false unless slurry?.encrypted?
    return false unless slurry.credentialsDeviceUuid == uuid
    slurry = _.cloneDeep slurry
    try
      slurry.encrypted = @encryption.decrypt slurry.encrypted
    catch error
      console.error error.stack
      return false

    # correctSig___ = @encryption.sign slurry
    # console.log JSON.stringify({correctSig___, slurrySignature}, null, 2)
    return @encryption.verify slurry, slurrySignature

  _userError: (message, code) =>
    error = new Error message
    error.code = code if code?
    return error

module.exports = CredentialsDeviceService
