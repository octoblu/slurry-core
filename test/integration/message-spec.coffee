{afterEach, beforeEach, describe, it} = global
{expect} = require 'chai'
sinon    = require 'sinon'

fs            = require 'fs'
request       = require 'request'
Encryption    = require 'meshblu-encryption'
enableDestroy = require 'server-destroy'
shmock        = require 'shmock'

MockStrategy  = require '../mock-strategy'
Server        = require '../../src/server'

describe 'messages', ->
  beforeEach (done) ->
    @privateKey = fs.readFileSync "#{__dirname}/../data/private-key.pem", 'utf8'
    @encryption = Encryption.fromPem @privateKey
    encrypted =
      secrets:
        credentials:
          secret: 'this is secret'
    @encrypted = @encryption.encrypt encrypted

    @meshblu = shmock 0xd00d
    enableDestroy @meshblu
    @apiStrategy = new MockStrategy name: 'api'
    @octobluStrategy = new MockStrategy name: 'octoblu'
    @messageHandler = onMessage: sinon.stub()

    @meshblu
      .get '/v2/whoami'
      .set 'Authorization', "Basic cGV0ZXI6aS1jb3VsZC1lYXQ="
      .reply 200, {
        options:
          imageUrl: "http://this-is-an-image.exe"
      }

    serverOptions =
      logFn: ->
      port: undefined,
      disableLogging: true
      apiStrategy: @apiStrategy
      octobluStrategy: @octobluStrategy
      messageHandler: @messageHandler
      configureHandler: {}
      serviceUrl: 'http://octoblu.xxx'
      deviceType: 'slurry-slurryr'
      meshbluConfig:
        hostname: 'localhost'
        protocol: 'http'
        port: 0xd00d
        uuid: 'peter'
        token: 'i-could-eat'
        privateKey: @privateKey
      appOctobluHost: 'http://app.octoblu.mom'
      userDeviceManagerUrl: 'http://manage-my.slurry'

    @server = new Server serverOptions

    @server.run (error) =>
      return done error if error?
      @serverPort = @server.address().port
      done()

  afterEach (done) ->
    @server.stop done

  afterEach (done) ->
    @meshblu.destroy done

  describe 'On POST /v1/messages', ->
    describe 'when authorized', ->
      beforeEach ->
        @credentialsDeviceAuth = new Buffer('cred-uuid:cred-token').toString 'base64'
        @meshblu
          .post '/authenticate'
          .set 'Authorization', "Basic #{@credentialsDeviceAuth}"
          .reply 204

      describe 'when we get some weird device instead of a credentials device', ->
        beforeEach ->
          serviceAuth = new Buffer('peter:i-could-eat').toString 'base64'
          credAuth = new Buffer('cred-uuid:cred-token').toString 'base64'

          @meshblu
            .get '/v2/devices/cred-uuid'
            .set 'Authorization', "Basic #{serviceAuth}"
            .reply 200,
              uuid: 'cred-uuid'
              banana: 'pudding'

          @replyToSender = @meshblu
            .post '/messages'
            .set 'Authorization', "Basic #{credAuth}"
            .reply 204

        describe 'when called with a valid message', ->
          beforeEach (done) ->
            options =
              baseUrl: "http://localhost:#{@serverPort}"
              headers:
                'x-meshblu-route': JSON.stringify [
                  {"from": "flow-uuid", "to": "user-device", "type": "message.sent"}
                  {"from": "user-device", "to": "cred-uuid", "type": "message.received"}
                ]
              json:
                metadata:
                  jobType: 'hello'
                data:
                  greeting: 'hola'
              auth:
                username: 'cred-uuid'
                password: 'cred-token'

            request.post '/v1/messages', options, (error, @response, @body) =>
              done error

          it 'should reply with an error to the whomever sent the message', ->
            @replyToSender.done()

          it 'should return a 400', ->
            expect(@response.statusCode).to.equal 400, JSON.stringify @body

      describe 'when we get an invalid credentials device', ->
        beforeEach ->
          serviceAuth = new Buffer('peter:i-could-eat').toString 'base64'
          credAuth = new Buffer('cred-uuid:cred-token').toString 'base64'

          @meshblu
            .get '/v2/devices/cred-uuid'
            .set 'Authorization', "Basic #{serviceAuth}"
            .reply 200,
                uuid: 'cred-uuid'
                slurrySignature: 'John Hancock. Definitely, definitely John Hancock'
                slurry:
                  credentialsDeviceUuid: 'cred-uuid'
                  encrypted: @encrypted

          @replyToSender = @meshblu
            .post '/messages'
            .set 'Authorization', "Basic #{credAuth}"
            .reply 204

        describe 'when called with a valid message', ->
          beforeEach (done) ->
            options =
              baseUrl: "http://localhost:#{@serverPort}"
              headers:
                'x-meshblu-route': JSON.stringify [
                  {"from": "flow-uuid", "to": "user-device", "type": "message.sent"}
                  {"from": "user-device", "to": "cred-uuid", "type": "message.received"}
                ]
              json:
                metadata:
                  jobType: 'hello'
                data:
                  greeting: 'hola'
              auth:
                username: 'cred-uuid'
                password: 'cred-token'

            request.post '/v1/messages', options, (error, @response, @body) =>
              done error

          it 'should reply with an error to the whomever sent the message', ->
            @replyToSender.done()

          it 'should return a 400', ->
            expect(@response.statusCode).to.equal 400, JSON.stringify @body

      describe 'when we have a real credentials device', ->
        beforeEach ->
          serviceAuth = new Buffer('peter:i-could-eat').toString 'base64'

          @meshblu
            .get '/v2/devices/cred-uuid'
            .set 'Authorization', "Basic #{serviceAuth}"
            .reply 200,
                uuid: 'cred-uuid'
                slurrySignature: 'LebOB6aPRQJC7HuLqVqwBeZOFITW+S+jTExlXKrnhvcbzgn6b82fwyh0Qin8ccMym9y4ymIWcKunfa9bZj2YsA=='
                slurry:
                  authorizedKey: 'some-uuid'
                  credentialsDeviceUuid: 'cred-uuid'
                  encrypted: @encrypted

        describe 'when called with a message without metadata', ->
          beforeEach (done) ->
            options =
              baseUrl: "http://localhost:#{@serverPort}"
              json:
                data:
                  greeting: 'hola'
              auth:
                username: 'cred-uuid'
                password: 'cred-token'

            request.post '/v1/messages', options, (error, @response, @body) =>
              done error

          it 'should return a 422', ->
            expect(@response.statusCode).to.equal 422, JSON.stringify(@body)

        describe 'when called with a valid message', ->
          beforeEach (done) ->
            @messageHandler.onMessage.yields null, metadata: {code: 200}, data: {whatever: 'this is a response'}
            @responseHandler = @meshblu
              .post '/messages'
              .set 'Authorization', "Basic #{@credentialsDeviceAuth}"
              .set 'x-meshblu-as', 'user-device'
              .send
                devices: ['flow-uuid']
                metadata:
                  code: 200
                  to: { foo: 'bar' }
                data:
                  whatever: 'this is a response'
              .reply 201

            options =
              baseUrl: "http://localhost:#{@serverPort}"
              headers:
                'x-meshblu-route': JSON.stringify [
                  {"from": "flow-uuid", "to": "user-device", "type": "message.sent"}
                  {"from": "user-device", "to": "cred-uuid", "type": "message.received"}
                ]
              json:
                metadata:
                  jobType: 'hello'
                  respondTo: { foo: 'bar' }
                data:
                  greeting: 'hola'
              auth:
                username: 'cred-uuid'
                password: 'cred-token'

            request.post '/v1/messages', options, (error, @response, @body) =>
              done error

          it 'should return a 201', ->
            expect(@response.statusCode).to.equal 201, JSON.stringify @body

          it 'should respond to the message via meshblu', ->
            @responseHandler.done()

          it 'should call the hello messageHandler with the message and auth', ->
            expect(@messageHandler.onMessage).to.have.been.calledWith sinon.match {
              encrypted:
                secrets:
                  credentials:
                    secret: 'this is secret'
            }, {
              metadata:
                jobType: 'hello'
              data:
                greeting: 'hola'
            }

        describe 'when called with a valid message, but theres an error', ->
          beforeEach (done) ->
            @messageHandler.onMessage.yields new Error 'Something very bad happened'
            @responseHandler = @meshblu
              .post '/messages'
              .set 'Authorization', "Basic #{@credentialsDeviceAuth}"
              .set 'x-meshblu-as', 'user-device'
              .send
                devices: ['flow-uuid']
                metadata:
                  code: 500
                  to: 'food'
                  error:
                    message: 'Something very bad happened'
              .reply 201

            options =
              baseUrl: "http://localhost:#{@serverPort}"
              headers:
                'x-meshblu-route': JSON.stringify [
                  {"from": "flow-uuid", "to": "user-device", "type": "message.sent"}
                  {"from": "user-device", "to": "cred-uuid", "type": "message.received"}
                ]
              json:
                metadata:
                  jobType: 'hello'
                  respondTo: 'food'
                data:
                  greeting: 'hola'
              auth:
                username: 'cred-uuid'
                password: 'cred-token'

            request.post '/v1/messages', options, (error, @response, @body) =>
              done error

          it 'should call the onMessage messageHandler with the message and auth', ->
            expect(@messageHandler.onMessage).to.have.been.calledWith sinon.match {
              encrypted:
                secrets:
                  credentials:
                    secret: 'this is secret'
            }, {
              metadata:
                jobType: 'hello'
              data:
                greeting: 'hola'
            }

          it 'should return a 500', ->
            expect(@response.statusCode).to.equal 500, JSON.stringify @body

          it 'should respond to the message with the error via meshblu', ->
            @responseHandler.done()

        describe 'when called with a valid message, but the the slurry is invalid', ->
          beforeEach (done) ->
            @messageHandler.onMessage.yields new Error 'Something very bad happened'
            @responseHandler = @meshblu
              .post '/messages'
              .set 'Authorization', "Basic #{@credentialsDeviceAuth}"
              .set 'x-meshblu-as', 'user-device'
              .send
                devices: ['flow-uuid']
                metadata:
                  code: 500
                  error:
                    message: 'Something very bad happened'
              .reply 201

            options =
              baseUrl: "http://localhost:#{@serverPort}"
              headers:
                'x-meshblu-route': JSON.stringify [
                  {"from": "flow-uuid", "to": "user-device", "type": "message.sent"}
                  {"from": "user-device", "to": "cred-uuid", "type": "message.received"}
                ]
              json:
                metadata:
                  jobType: 'hello'
                data:
                  greeting: 'hola'
              auth:
                username: 'cred-uuid'
                password: 'cred-token'

            request.post '/v1/messages', options, (error, @response, @body) =>
              done error

          it 'should call the hello messageHandler with the message and auth', ->
            expect(@messageHandler.onMessage).to.have.been.calledWith sinon.match {
              metadata:
                jobType: 'hello'
              data:
                greeting: 'hola'
              encrypted:
                secrets:
                  credentials:
                    secret: 'this is secret'
            }

          it 'should return a 500', ->
            expect(@response.statusCode).to.equal 500, JSON.stringify @body

          it 'should respond to the message with the error via meshblu', ->
            @responseHandler.done()
