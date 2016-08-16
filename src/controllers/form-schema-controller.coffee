class FormSchemaController
  constructor: ({@messagesService, @configureService}) ->
    throw new Error 'messagesService is required' unless @messagesService?
    throw new Error 'configureService is required' unless @configureService?

  list: (req, res) =>
    @messagesService.formSchema (error, messageSchema) =>
      return res.sendError error if error?

      @configureService.formSchema (error, configureSchema) =>
        return res.sendError error if error?

        schema = {
          message: messageSchema.message
          configure: configureSchema.configure
        }
        return res.send schema

module.exports = FormSchemaController
