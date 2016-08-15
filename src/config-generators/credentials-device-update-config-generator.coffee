module.exports = ({slurry, slurrySignature, serviceUrl}) ->
  $set:
    'slurry':               slurry
    'slurrySignature':      slurrySignature
    'meshblu.forwarders.message.received': [{
      type: 'webhook'
      url:  "#{serviceUrl}/v1/messages",
      method: 'POST'
      generateAndForwardMeshbluCredentials: true
    }]
    'meshblu.forwarders.configure.received': [{
      type: 'webhook'
      url:  "#{serviceUrl}/v1/configure",
      method: 'POST'
      generateAndForwardMeshbluCredentials: true
    }]
