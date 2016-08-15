_     = require 'lodash'
debug = require('debug')('slurry-core:messages-controller')

class ConfigureController
  constructor: ({@credentialsDeviceService, @configureService}) ->

  create: (req, res) =>
    route     = req.get 'x-meshblu-route'
    auth      = req.meshbluAuth
    message   = req.body
    respondTo = _.get message, 'metadata.respondTo'

    debug 'create', auth.uuid
    @credentialsDeviceService.getslurryByUuid auth.uuid, (error, slurry) =>
      debug 'credentialsDeviceService.getslurryByUuid', error
      return @respondWithError {auth, error, res, route, respondTo} if error?

      @configureService.send {auth, slurry, message}, (error, response) =>
        debug 'configureService.send', error
        return @respondWithError {auth, error, res, route, respondTo} if error?

        @configureService.reply {auth, route, response, respondTo}, (error) =>
          debug 'configureService.reply', error
          return @respondWithError {auth, error, res, route, respondTo} if error?

          res.sendStatus 201

  respondWithError: ({auth, error, res, route, respondTo}) =>
    @configureService.replyWithError {auth, error, route, respondTo}, (newError) =>
      return res.sendError newError if newError?
      return res.sendError error


module.exports = ConfigureController
