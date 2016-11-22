module.exports = (options) ->
  {
    authorizedUuid
    credentialsUuid
    deviceType
    formSchemaUrl
    imageUrl
    messageSchemaUrl
    resourceOwnerName
    responseSchemaUrl
    configureSchemaUrl
  } = options

  return {
    name: resourceOwnerName
    type: deviceType
    logo: imageUrl
    owner: authorizedUuid
    online: true
    octoblu:
      flow:
        forwardMetadata: true
    schemas:
      version: '2.0.0'
      form:
        $ref: formSchemaUrl
      configure:
        $ref: configureSchemaUrl
      message:
        $ref: messageSchemaUrl
      response:
        $ref: responseSchemaUrl
    meshblu:
      version: '2.0.0'
      whitelists:
        broadcast:
          as:       [{uuid: authorizedUuid}, {uuid: credentialsUuid}]
          received: [{uuid: authorizedUuid}]
          sent:     [{uuid: authorizedUuid}]
        configure:
          as:       [{uuid: authorizedUuid}]
          received: [{uuid: authorizedUuid}]
          sent:     [{uuid: authorizedUuid}, {uuid: credentialsUuid}]
          update:   [{uuid: authorizedUuid}]
        discover:
          view:     [{uuid: authorizedUuid}, {uuid: credentialsUuid}]
          as:       [{uuid: authorizedUuid}]
        message:
          as:       [{uuid: authorizedUuid}, {uuid: credentialsUuid}]
          received: [{uuid: authorizedUuid}, {uuid: credentialsUuid}]
          sent:     [{uuid: authorizedUuid}]
          from:     [{uuid: authorizedUuid}]
  }
