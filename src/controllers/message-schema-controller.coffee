class MessageSchemaController
  constructor: ({@messagesService}) ->
    throw new Error 'messagesService is required' unless @messagesService?

  list: (req, res) =>
    @messagesService.messageSchema (error, schema) =>
      return res.sendError error if error?
      return res.send schema


module.exports = MessageSchemaController
