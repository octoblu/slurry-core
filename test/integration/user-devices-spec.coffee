{afterEach, beforeEach, describe, it} = global
{expect} = require 'chai'

fs            = require 'fs'
Encryption    = require 'meshblu-encryption'
request       = require 'request'
enableDestroy = require 'server-destroy'
shmock        = require 'shmock'

MockStrategy  = require '../mock-strategy'
Server        = require '../../src/server'

describe 'User Devices Spec', ->
  beforeEach (done) ->
    @meshblu = shmock 0xd00d
    enableDestroy @meshblu

    @privateKey = fs.readFileSync "#{__dirname}/../data/private-key.pem", 'utf8'

    encryption = Encryption.fromPem @privateKey
    @encrypted = encryption.encrypt 'this is secret'

    @apiStrategy = new MockStrategy name: 'lib'
    @octobluStrategy = new MockStrategy name: 'octoblu'

    serverOptions =
      logFn: ->
      messageHandler: {}
      configureHandler: {}
      port: undefined,
      disableLogging: true
      apiStrategy: @apiStrategy
      apiName: 'github'
      deviceType: 'slurry-core'
      octobluStrategy: @octobluStrategy
      serviceUrl: 'http://octoblu.xxx'
      meshbluConfig:
        hostname: 'localhost'
        protocol: 'http'
        port: 0xd00d
        uuid: 'peter'
        token: 'i-could-eat'
        privateKey: @privateKey
      appOctobluHost: 'http://app.octoblu.rentals'
      userDeviceManagerUrl: 'http://manage-my.slurry'

    @meshblu
      .get '/v2/whoami'
      .set 'Authorization', "Basic cGV0ZXI6aS1jb3VsZC1lYXQ="
      .reply 200, {
        options:
          imageUrl: "http://this-is-an-image.exe"
          resourceOwnerName: 'resource owner name'
      }

    @server = new Server serverOptions

    @server.run (error) =>
      return done error if error?
      @serverPort = @server.address().port
      done()

  afterEach (done) ->
    @server.stop done

  afterEach (done) ->
    @meshblu.destroy done

  describe 'On GET /cred-uuid/user-devices', ->
    describe 'when authorized', ->
      beforeEach (done) ->
        userAuth = new Buffer('some-uuid:some-token').toString 'base64'
        serviceAuth = new Buffer('peter:i-could-eat').toString 'base64'
        credentialsDeviceAuth = new Buffer('cred-uuid:cred-token2').toString 'base64'

        @meshblu
          .post '/authenticate'
          .set 'Authorization', "Basic #{userAuth}"
          .reply 204

        @meshblu
          .post '/search/devices'
          .send uuid: 'cred-uuid', 'slurry.authorizedKey': "pG7eYd4TYZOX2R5S73jo9aexPzldiNo4pw1wViDpYrAAGRMT6dY0jlbXbfHMz9y+El6AcXMZJEOxaeO1lITsYg=="
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, [
            uuid: 'cred-uuid'
            slurrySignature: 'nu4y/MUxq7LsRTWhgnRKdsqG83jNJvXaY5ztVy22lmU0He984NDq8I3O/SudG1EVyhGwAv00nGxrwmFqq9QnyQ=='
            slurry:
              authorizedKey: 'some-uuid'
              credentialsDeviceUuid: 'cred-uuid'
              encrypted: @encrypted
          ]

        @meshblu
          .post '/devices/cred-uuid/tokens'
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, uuid: 'cred-uuid', token: 'cred-token2'

        @meshblu
          .get '/v2/devices/cred-uuid/subscriptions'
          .set 'Authorization', "Basic #{credentialsDeviceAuth}"
          .reply 200, [
            {emitterUuid: 'first-user-uuid', type: 'message.received'}
            {emitterUuid: 'second-user-uuid',type: 'message.received'}
            {emitterUuid: 'whatever-user-uuid', type: 'message.sent'}
            {emitterUuid: 'cred-uuid', type: 'message.received'}
          ]

        options =
          baseUrl: "http://localhost:#{@serverPort}"
          json: true
          auth:
            username: 'some-uuid'
            password: 'some-token'

        request.get '/credentials/cred-uuid/user-devices', options, (error, @response, @body) =>
          done error

      it 'should return a 200', ->
        expect(@response.statusCode).to.equal 200

      it 'should return the list of user devices', ->
        expect(@body).to.deep.equal [
          {uuid: 'first-user-uuid'}
          {uuid: 'second-user-uuid'}
        ]

    describe 'when inauthentic', ->
      beforeEach (done) ->
        userAuth = new Buffer('some-uuid:some-token').toString 'base64'
        serviceAuth = new Buffer('peter:i-could-eat').toString 'base64'
        credentialsDeviceAuth = new Buffer('cred-uuid:cred-token2').toString 'base64'

        @meshblu
          .post '/authenticate'
          .set 'Authorization', "Basic #{userAuth}"
          .reply 204

        @meshblu
          .post '/search/devices'
          .send uuid: 'cred-uuid', 'slurry.authorizedKey': 'pG7eYd4TYZOX2R5S73jo9aexPzldiNo4pw1wViDpYrAAGRMT6dY0jlbXbfHMz9y+El6AcXMZJEOxaeO1lITsYg=='
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, []

        @meshblu
          .post '/devices/cred-uuid/tokens'
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, uuid: 'cred-uuid', token: 'cred-token2'

        @meshblu
          .get '/v2/devices/cred-uuid/subscriptions'
          .set 'Authorization', "Basic #{credentialsDeviceAuth}"
          .reply 200, [
            {uuid: 'first-user-uuid', type: 'message.received'}
            {uuid: 'second-user-uuid',type: 'message.received'}
            {uuid: 'whatever-user-uuid', type: 'message.sent'}
          ]

        options =
          baseUrl: "http://localhost:#{@serverPort}"
          json: true
          auth:
            username: 'some-uuid'
            password: 'some-token'

        request.get '/credentials/cred-uuid/user-devices', options, (error, @response, @body) =>
          done error

      it 'should return a 404', ->
        expect(@response.statusCode).to.equal 404

    describe 'when authorized, but with a bad credentials device', ->
      beforeEach (done) ->
        userAuth = new Buffer('some-uuid:some-token').toString 'base64'
        serviceAuth = new Buffer('peter:i-could-eat').toString 'base64'

        @meshblu
          .post '/authenticate'
          .set 'Authorization', "Basic #{userAuth}"
          .reply 204

        @meshblu
          .post '/search/devices'
          .send uuid: 'bad-cred-uuid', 'slurry.authorizedKey': "pG7eYd4TYZOX2R5S73jo9aexPzldiNo4pw1wViDpYrAAGRMT6dY0jlbXbfHMz9y+El6AcXMZJEOxaeO1lITsYg=="
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, [
            uuid: 'bad-cred-uuid'
            slurry:
              authorizedKey: 'some-uuid'
              credentialsDeviceUuid: 'cred-uuid'
              encrypted: @encrypted
          ]

        options =
          baseUrl: "http://localhost:#{@serverPort}"
          json: true
          auth:
            username: 'some-uuid'
            password: 'some-token'

        request.get '/credentials/bad-cred-uuid/user-devices', options, (error, @response, @body) =>
          done error

      it 'should return a 404', ->
        expect(@response.statusCode).to.equal 404, JSON.stringify @body

  describe 'On POST /cred-uuid/user-devices', ->
    describe 'when authorized', ->
      beforeEach (done) ->
        userAuth = new Buffer('some-uuid:some-token').toString 'base64'
        serviceAuth = new Buffer('peter:i-could-eat').toString 'base64'
        credentialsDeviceAuth = new Buffer('cred-uuid:cred-token2').toString 'base64'
        userDeviceAuth = new Buffer('user_device_uuid:user_device_token').toString 'base64'

        @meshblu
          .post '/authenticate'
          .set 'Authorization', "Basic #{userAuth}"
          .reply 200, uuid: 'some-uuid', token: 'some-token'

        @meshblu
          .post '/search/devices'
          .send uuid: 'cred-uuid', 'slurry.authorizedKey': 'pG7eYd4TYZOX2R5S73jo9aexPzldiNo4pw1wViDpYrAAGRMT6dY0jlbXbfHMz9y+El6AcXMZJEOxaeO1lITsYg=='
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, [
            uuid: 'cred-uuid'
            slurrySignature: 'OLE06dTcCpQni4qWRxRnRwtzm1XBrkflhQeAdbHCeJgwzjXvvTv6kKcWrV+0zkPaQavWANNKg/EZsnY7kq7TmQ=='
            slurry:
              credentialsDeviceUuid: 'cred-uuid'
              encrypted: @encrypted
          ]

        @meshblu
          .post '/devices/cred-uuid/tokens'
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, uuid: 'cred-uuid', token: 'cred-token2'

        @createUserDevice = @meshblu
          .post '/devices'
          .send
            type: "slurry-core"
            logo: "http://this-is-an-image.exe"
            owner: 'some-uuid'
            online: true
            octoblu:
              flow:
                forwardMetadata: true
            schemas:
              version: '2.0.0'
              form:
                $ref: 'http://octoblu.xxx/v1/form-schema'
              configure:
                $ref: 'http://octoblu.xxx/v1/configure-schema'
              message:
                $ref: 'http://octoblu.xxx/v1/message-schema'
              response:
                $ref: 'http://octoblu.xxx/v1/response-schema'
            meshblu:
              version: '2.0.0'
              whitelists:
                broadcast:
                  as: [{uuid: 'some-uuid'}, {uuid: 'cred-uuid'}]
                  received: [{uuid: 'some-uuid'}]
                  sent: [{uuid: 'some-uuid'}]
                configure:
                  as: [{uuid: 'some-uuid'}]
                  received: [{uuid: 'some-uuid'}]
                  sent: [{uuid: 'some-uuid'}, {uuid: 'cred-uuid'}]
                  update: [{uuid: 'some-uuid'}]
                discover:
                  view: [{uuid: 'some-uuid'}, {uuid: 'cred-uuid'}]
                  as: [{uuid: 'some-uuid'}]
                message:
                  as: [{uuid: 'some-uuid'}, {uuid: 'cred-uuid'}]
                  received: [{uuid: 'some-uuid'}, {uuid: 'cred-uuid'}]
                  sent: [{uuid: 'some-uuid'}]
                  from: [{uuid: 'some-uuid'}]
          .reply 201, uuid: 'user_device_uuid', token: 'user_device_token'

        @createStatusDevice = @meshblu
          .post '/devices'
          .send
            type: "status-device"
            owner: "user_device_uuid"
            meshblu:
              whitelists:
                version: "2.0.0"
                configure:
                  update: [
                    {uuid: "cred-uuid"}
                    {uuid: "user_device_uuid"}
                    {uuid: "some-uuid"}
                  ]
                  sent: [
                    {uuid: "user_device_uuid"}
                    {uuid: "some-uuid"}
                  ]
                discover:
                  view: [
                    {uuid: "cred-uuid"}
                    {uuid: "user_device_uuid"}
                    {uuid: "some-uuid"}
                  ]
          .reply 201, {}

        @meshblu
          .put '/v2/devices/user_device_uuid'
          .set 'Authorization', "Basic #{userDeviceAuth}"
          .reply 204

        @createMessageReceivedSubscription = @meshblu
          .post '/v2/devices/cred-uuid/subscriptions/user_device_uuid/message.received'
          .set 'Authorization', "Basic #{credentialsDeviceAuth}"
          .reply 201

        @createConfigureSentSubscription = @meshblu
          .post '/v2/devices/cred-uuid/subscriptions/user_device_uuid/configure.sent'
          .set 'Authorization', "Basic #{credentialsDeviceAuth}"
          .reply 201

        options =
          baseUrl: "http://localhost:#{@serverPort}"
          json: true
          headers:
            Authorization: "Bearer #{userAuth}"

        request.post '/credentials/cred-uuid/user-devices', options, (error, @response, @body) =>
          done error

      it 'should create the user device', ->
        @createUserDevice.done()

      it "should subscribe the credentials-device to the user device's received messages", ->
        @createMessageReceivedSubscription.done()

      it "should subscribe the credentials-device to the user device's configure.sent", ->
        @createConfigureSentSubscription.done()

      it 'should return a 201', ->
        expect(@response.statusCode).to.equal 201

      it 'should return the user device', ->
        expect(@body).to.deep.equal uuid: 'user_device_uuid', token: 'user_device_token'

  describe 'On DELETE /cred-uuid/user-devices/user_device_uuid', ->
    describe 'when authorized', ->
      beforeEach (done) ->
        userAuth = new Buffer('some-uuid:some-token').toString 'base64'
        serviceAuth = new Buffer('peter:i-could-eat').toString 'base64'
        credentialsDeviceAuth = new Buffer('cred-uuid:cred-token2').toString 'base64'

        @meshblu
          .post '/authenticate'
          .set 'Authorization', "Basic #{userAuth}"
          .reply 204

        @meshblu
          .post '/search/devices'
          .send uuid: 'cred-uuid', 'slurry.authorizedKey': 'pG7eYd4TYZOX2R5S73jo9aexPzldiNo4pw1wViDpYrAAGRMT6dY0jlbXbfHMz9y+El6AcXMZJEOxaeO1lITsYg=='
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, [
            uuid: 'cred-uuid'
            slurrySignature: 'OLE06dTcCpQni4qWRxRnRwtzm1XBrkflhQeAdbHCeJgwzjXvvTv6kKcWrV+0zkPaQavWANNKg/EZsnY7kq7TmQ=='
            slurry:
              credentialsDeviceUuid: 'cred-uuid'
              encrypted: @encrypted
          ]

        @meshblu
          .post '/devices/cred-uuid/tokens'
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, uuid: 'cred-uuid', token: 'cred-token2'

        @deleteMessageReceivedSubscription = @meshblu
          .delete '/v2/devices/cred-uuid/subscriptions/user_device_uuid/message.received'
          .set 'Authorization', "Basic #{credentialsDeviceAuth}"
          .reply 201

        @deleteConfigureSentSubscription = @meshblu
          .delete '/v2/devices/cred-uuid/subscriptions/user_device_uuid/configure.sent'
          .set 'Authorization', "Basic #{credentialsDeviceAuth}"
          .reply 201

        options =
          baseUrl: "http://localhost:#{@serverPort}"
          json: true
          headers:
            Authorization: "Bearer #{userAuth}"

        request.delete '/credentials/cred-uuid/user-devices/user_device_uuid', options, (error, @response, @body) =>
          done error

      it "should delete the subscription from the credentials-device to the user device's received messages", ->
        @deleteMessageReceivedSubscription.done()

      it "should delete the subscription from the credentials-device to the user device's configure.sent", ->
        @deleteConfigureSentSubscription.done()

      it 'should return a 204', ->
        expect(@response.statusCode).to.equal 204

      it 'should return nothing', ->
        expect(@body).to.be.empty

  describe 'On DELETE /cred-uuid/user-devices/cred-uuid', ->
    describe 'when authorized', ->
      beforeEach (done) ->
        userAuth = new Buffer('some-uuid:some-token').toString 'base64'
        serviceAuth = new Buffer('peter:i-could-eat').toString 'base64'

        @meshblu
          .post '/authenticate'
          .set 'Authorization', "Basic #{userAuth}"
          .reply 204

        @meshblu
          .post '/search/devices'
          .send uuid: 'cred-uuid', 'slurry.authorizedKey': 'pG7eYd4TYZOX2R5S73jo9aexPzldiNo4pw1wViDpYrAAGRMT6dY0jlbXbfHMz9y+El6AcXMZJEOxaeO1lITsYg=='
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, [
            uuid: 'cred-uuid'
            slurrySignature: 'OLE06dTcCpQni4qWRxRnRwtzm1XBrkflhQeAdbHCeJgwzjXvvTv6kKcWrV+0zkPaQavWANNKg/EZsnY7kq7TmQ=='
            slurry:
              credentialsDeviceUuid: 'cred-uuid'
              encrypted: @encrypted
          ]

        @meshblu
          .post '/devices/cred-uuid/tokens'
          .set 'Authorization', "Basic #{serviceAuth}"
          .reply 200, uuid: 'cred-uuid', token: 'cred-token2'

        options =
          baseUrl: "http://localhost:#{@serverPort}"
          json: true
          headers:
            Authorization: "Bearer #{userAuth}"

        request.delete '/credentials/cred-uuid/user-devices/cred-uuid', options, (error, @response, @body) =>
          done error

      it 'should return a 403', ->
        expect(@response.statusCode).to.equal 403, JSON.stringify @body
