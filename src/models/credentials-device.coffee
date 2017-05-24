_           = require 'lodash'
async       = require 'async'
MeshbluHTTP = require 'meshblu-http'
Encryption  = require 'meshblu-encryption'
url         = require 'url'

credentialsDeviceUpdateGenerator = require '../config-generators/credentials-device-update-config-generator'
userDeviceConfigGenerator = require '../config-generators/user-device-config-generator'
statusDeviceConfigGenerator = require '../config-generators/status-device-create-config-generator'

class CredentialsDevice
  constructor: ({@deviceType, @encrypted, @imageUrl, @meshbluConfig, @serviceUrl, @serviceUuid}) ->
    throw new Error('deviceType is required') unless @deviceType?
    throw new Error('serviceUuid is required') unless @serviceUuid?
    {@uuid, @privateKey} = @meshbluConfig

    @encryption = Encryption.fromJustGuess @privateKey
    @meshblu    = new MeshbluHTTP @meshbluConfig

  createUserDevice: ({authorizedUuid}, callback) =>
    resourceOwnerName = @encryption.decrypt(@encrypted).username

    userDeviceConfig = userDeviceConfigGenerator
      authorizedUuid: authorizedUuid
      credentialsUuid: @uuid
      deviceType: @deviceType
      imageUrl: @imageUrl
      resourceOwnerName: resourceOwnerName
      formSchemaUrl: @_getFormSchemaUrl()
      messageSchemaUrl: @_getMessageSchemaUrl()
      configureSchemaUrl: @_getConfigureSchemaUrl()
      responseSchemaUrl: @_getResponseSchemaUrl()

    @meshblu.register userDeviceConfig, (error, userDevice) =>
      return callback error if error?

      subscription = {subscriberUuid: @uuid, emitterUuid: userDevice.uuid, type: 'message.received'}
      @meshblu.createSubscription subscription, (error) =>
        return callback error if error?

        subscription = {subscriberUuid: @uuid, emitterUuid: userDevice.uuid, type: 'configure.sent'}
        @meshblu.createSubscription subscription, (error) =>
          return callback error if error?
          statusDeviceOptions = {credentialsDeviceUuid: @uuid, userDeviceUuid: userDevice.uuid, authorizedUuid}
          @createStatusDevice statusDeviceOptions, (error, {uuid}={}) =>
            callback error if error?

            userDeviceOptions = {
              userDeviceUuid: userDevice.uuid
              userDeviceToken: userDevice.token
              statusDeviceUuid: uuid
            }
            @updateUserDeviceWithStatusDevice userDeviceOptions, (error) =>
              callback error, userDevice

  createStatusDevice: ({credentialsDeviceUuid, userDeviceUuid, authorizedUuid}, callback) =>
    statusDeviceConfig = statusDeviceConfigGenerator {credentialsDeviceUuid, userDeviceUuid, authorizedUuid}
    @meshblu.register statusDeviceConfig, callback

  updateUserDeviceWithStatusDevice: ({userDeviceUuid, userDeviceToken, statusDeviceUuid}, callback) =>
    userDeviceMeshblu = new MeshbluHTTP _.defaults {uuid: userDeviceUuid, token: userDeviceToken}, @meshbluConfig
    update =
      $set:
        statusDevice: statusDeviceUuid
        status: $ref: "meshbludevice://#{statusDeviceUuid}/#/status"
    userDeviceMeshblu.updateDangerously userDeviceUuid, update, callback

  deleteUserDeviceSubscription: ({userDeviceUuid}, callback) =>
    return callback @_userError 'Cannot remove the credentials subscription to itself', 403 if userDeviceUuid == @uuid
    subscription =
      emitterUuid: userDeviceUuid
      subscriberUuid: @uuid
      type: 'message.received'

    @meshblu.deleteSubscription subscription, (error, ignored) =>
      return callback error if error?

      subscription =
        emitterUuid: userDeviceUuid
        subscriberUuid: @uuid
        type: 'configure.sent'

      @meshblu.deleteSubscription subscription, (error, ignored) =>
        callback error

  getPublicDevice: (callback) =>
    @meshblu.device @serviceUuid, (error, credentialsDevice) =>
      return callback error if error?
      decrypted = @encryption.decrypt @encrypted
      decrypted = _.omit decrypted, 'secrets'
      return callback null, _.defaults({username: decrypted.username}, credentialsDevice.options)

  getUserDevices: (callback) =>
    @meshblu.subscriptions @uuid, (error, subscriptions) =>
      return callback error if error?
      return callback null, @_userDevicesFromSubscriptions subscriptions

  getUuid: => @uuid

  update: ({authorizedUuid, encrypted, id}, callback) =>
    {slurry, slurrySignature} = @_getSignedUpdate {authorizedUuid, encrypted, id}
    slurry.encrypted = @encryption.encrypt slurry.encrypted

    update = credentialsDeviceUpdateGenerator {slurry, slurrySignature, @serviceUrl}
    @meshblu.updateDangerously @uuid, update, (error) =>
      return callback error if error?
      @_updateUserDevices (error) =>
        return callback error if error?
        @_subscribeToOwnMessagesReceived (error) =>
          return callback error if error?
          @_subscribeToOwnConfigureReceived callback

  _updateUserDevices: (callback) =>
    @getUserDevices (error, devices) =>
      return callback error if error?
      async.each devices, (device, next) =>
        update = $set: credentialsDeviceUpdatedAt: Date.now()
        @meshblu.updateDangerously device.uuid, update, next
      , callback

  _getConfigureSchemaUrl: =>
    uri = url.parse @serviceUrl
    uri.pathname = "#{uri.pathname}v1/configure-schema"
    return url.format uri

  _getFormSchemaUrl: =>
    uri = url.parse @serviceUrl
    uri.pathname = "#{uri.pathname}v1/form-schema"
    return url.format uri

  _getMessageSchemaUrl: =>
    uri = url.parse @serviceUrl
    uri.pathname = "#{uri.pathname}v1/message-schema"
    return url.format uri

  _getResponseSchemaUrl: =>
    uri = url.parse @serviceUrl
    uri.pathname = "#{uri.pathname}v1/response-schema"
    return url.format uri

  _getSignedUpdate: ({authorizedUuid, encrypted, id}) =>
    slurry = {
      authorizedKey: @encryption.sign(authorizedUuid).toString 'base64'
      idKey:         @encryption.sign(id).toString 'base64'
      credentialsDeviceUuid: @uuid
      version: '1.0.0'
      encrypted: encrypted
    }
    slurrySignature = @encryption.sign slurry
    return {slurry, slurrySignature}

  _subscribeToOwnMessagesReceived: (callback) =>
    subscription = {subscriberUuid: @uuid, emitterUuid: @uuid, type: 'message.received'}
    @meshblu.createSubscription subscription, (error, ignored) =>
      return callback error if error?
      return callback()

  _subscribeToOwnConfigureReceived: (callback) =>
    subscription = {subscriberUuid: @uuid, emitterUuid: @uuid, type: 'configure.received'}
    @meshblu.createSubscription subscription, (error, ignored) =>
      return callback error if error?
      return callback()

  _userDevicesFromSubscriptions: (subscriptions) =>
    _(subscriptions)
      .filter type: 'message.received'
      .reject emitterUuid: @uuid
      .map ({emitterUuid}) => {uuid: emitterUuid}
      .value()

  _userError: (message, code) =>
    error = new Error message
    error.code = code if code?
    return error

module.exports = CredentialsDevice
