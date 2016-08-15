class ConfigureSchemaController
  constructor: ({@configureService}) ->
    throw new Error 'configureService is required' unless @configureService?

  list: (req, res) =>
    @configureService.configureSchema (error, schema) =>
      return res.sendError error if error?
      return res.send schema


module.exports = ConfigureSchemaController
