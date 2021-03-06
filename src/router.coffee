MeshbluAuth = require 'express-meshblu-auth'
passport    = require 'passport'

CredentialsDeviceController = require './controllers/credentials-device-controller'
FormSchemaController        = require './controllers/form-schema-controller'
MessagesController          = require './controllers/messages-controller'
ConfigureController         = require './controllers/configure-controller'
MessageSchemaController     = require './controllers/message-schema-controller'
ConfigureSchemaController   = require './controllers/configure-schema-controller'
OctobluAuthController       = require './controllers/octoblu-auth-controller'
ResponseSchemaController    = require './controllers/response-schema-controller'
StaticSchemasController     = require './controllers/static-schemas-controller'
UserDevicesController       = require './controllers/user-devices-controller'

class Router
  constructor: (options) ->
    {
      @appOctobluHost
      @credentialsDeviceService
      @messagesService
      @configureService
      @meshbluConfig
      @serviceUrl
      @userDeviceManagerUrl
      @staticSchemasPath
      @skipRedirectAfterApiAuth
    } = options

    throw new Error 'appOctobluHost is required' unless @appOctobluHost?
    throw new Error 'credentialsDeviceService is required' unless @credentialsDeviceService?
    throw new Error 'meshbluConfig is required' unless @meshbluConfig?
    throw new Error 'messagesService is required' unless @messagesService?
    throw new Error 'configureService is required' unless @configureService?
    throw new Error 'serviceUrl is required' unless @serviceUrl?
    throw new Error 'userDeviceManagerUrl is required' unless @userDeviceManagerUrl?

    @credentialsDeviceController = new CredentialsDeviceController {@credentialsDeviceService, @appOctobluHost, @serviceUrl, @userDeviceManagerUrl}
    @formSchemaController        = new FormSchemaController {@messagesService, @configureService}
    @messagesController          = new MessagesController {@credentialsDeviceService, @messagesService}
    @configureController         = new ConfigureController {@credentialsDeviceService, @configureService}
    @messageSchemaController     = new MessageSchemaController {@messagesService}
    @configureSchemaController   = new ConfigureSchemaController {@configureService}
    @octobluAuthController       = new OctobluAuthController
    @responseSchemaController    = new ResponseSchemaController {@messagesService}
    @staticSchemasController     = new StaticSchemasController {@staticSchemasPath}
    @userDevicesController       = new UserDevicesController

  route: (app) =>
    meshbluAuth = new MeshbluAuth @meshbluConfig

    app.get '/', (req, res) => res.redirect('/auth/octoblu')
    app.get '/v1/form-schema', @formSchemaController.list
    app.get '/v1/message-schema', @messageSchemaController.list
    app.get '/v1/response-schema', @responseSchemaController.list
    app.get '/v1/configure-schema', @configureSchemaController.list
    app.get '/schemas/:name', @staticSchemasController.get

    app.get '/auth/octoblu', passport.authenticate('octoblu')
    app.get '/auth/octoblu/callback', passport.authenticate('octoblu', failureRedirect: '/auth/octoblu'), @octobluAuthController.storeAuthAndRedirect

    app.use meshbluAuth.auth()
    app.use meshbluAuth.gatewayRedirect('/auth/octoblu')

    upsert = @credentialsDeviceController.upsertWithRedirect
    upsert = @credentialsDeviceController.upsertWithoutRedirect if @skipRedirectAfterApiAuth

    app.get  '/auth/api', passport.authenticate('api')
    app.get  '/auth/api/callback', passport.authenticate('api'), upsert
    app.post  '/auth/api/callback', passport.authenticate('api'), upsert

    app.post '/v1/messages', @messagesController.create
    app.post '/v1/configure', @configureController.create

    app.all  '/credentials/:credentialsDeviceUuid*', @credentialsDeviceController.getCredentialsDevice
    app.get  '/credentials/:credentialsDeviceUuid', @credentialsDeviceController.get
    app.get  '/credentials/:credentialsDeviceUuid/user-devices', @userDevicesController.list
    app.post '/credentials/:credentialsDeviceUuid/user-devices', @userDevicesController.create
    app.delete  '/credentials/:credentialsDeviceUuid/user-devices/:userDeviceUuid', @userDevicesController.delete


    app.use (req, res) => res.redirect '/auth/api'

module.exports = Router
