cors           = require 'cors'
cookieParser   = require 'cookie-parser'
cookieSession  = require 'cookie-session'
MeshbluHTTP    = require 'meshblu-http'
passport       = require 'passport'

octobluExpress = require 'express-octoblu'

Router                   = require './router'
CredentialsDeviceService = require './services/credentials-device-service'
MessagesService          = require './services/messages-service'
ConfigureService         = require './services/configure-service'

class Server
  constructor: (options) ->
    {
      @apiStrategy
      @appOctobluHost
      @deviceType
      @meshbluConfig
      @messageHandler
      @configureHandler
      @octobluStrategy
      @schemas
      @serviceUrl
      @userDeviceManagerUrl
      @disableLogging
      @logFn
      @port
      @staticSchemasPath
      @skipRedirectAfterApiAuth
    } = options

    throw new Error 'schemas not allowed' if @schemas?
    throw new Error 'Missing required parameter: apiStrategy'          unless @apiStrategy?
    throw new Error 'Missing required parameter: appOctobluHost'       unless @appOctobluHost?
    throw new Error 'Missing required parameter: deviceType'           unless @deviceType?
    throw new Error 'Missing required parameter: meshbluConfig'        unless @meshbluConfig?
    throw new Error 'Missing required parameter: messageHandler'       unless @messageHandler?
    throw new Error 'Missing required parameter: configureHandler'     unless @configureHandler?
    throw new Error 'Missing required parameter: octobluStrategy'      unless @octobluStrategy?
    throw new Error 'Missing required parameter: serviceUrl'           unless @serviceUrl?
    throw new Error 'Missing required parameter: userDeviceManagerUrl' unless @userDeviceManagerUrl?

  address: =>
    @server.address()

  run: (callback) =>
    passport.serializeUser   (user, done) => done null, user
    passport.deserializeUser (user, done) => done null, user

    passport.use 'octoblu', @octobluStrategy
    passport.use 'api', @apiStrategy

    app = octobluExpress({ @disableLogging, @logFn })
    app.use cors(exposedHeaders: ['Location'])
    app.use cookieSession secret: @meshbluConfig.token
    app.use cookieParser()
    app.use passport.initialize()
    app.use passport.session()

    meshblu = new MeshbluHTTP @meshbluConfig
    meshblu.whoami (error, device) =>
      throw new Error("Could not authenticate with meshblu!: #{error.message}") if error?
      {imageUrl} = device.options ? {}
      credentialsDeviceService  = new CredentialsDeviceService { @deviceType, imageUrl, @meshbluConfig, @serviceUrl }
      messagesService           = new MessagesService { @messageHandler, @schemas, @meshbluConfig }
      configureService          = new ConfigureService { @configureHandler, @schemas, @meshbluConfig }
      router = new Router {
        credentialsDeviceService
        messagesService
        configureService
        @appOctobluHost
        @meshbluConfig
        @serviceUrl
        @userDeviceManagerUrl
        @staticSchemasPath
        @skipRedirectAfterApiAuth
      }
      router.route app

      @server = app.listen @port, callback

  stop: (callback) =>
    @server.close callback

module.exports = Server
