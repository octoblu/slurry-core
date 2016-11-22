debug = require('debug')('slurry-core:messages-controller')

class ConfigureController
  constructor: ({@credentialsDeviceService, @configureService}) ->

  create: (req, res) =>
    route  = req.get 'x-meshblu-route'
    auth   = req.meshbluAuth
    config = req.body

    debug 'create', auth.uuid
    @credentialsDeviceService.getSlurryByUuid auth.uuid, (error, slurry) =>
      debug 'credentialsDeviceService.getSlurryByUuid', error
      return res.sendError error if error?

      @configureService.configure {auth, slurry, config, route}, (error) =>
        debug 'configureService.configure', error
        return res.sendError error if error?

        res.sendStatus 201

module.exports = ConfigureController
