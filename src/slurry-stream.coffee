{EventEmitter} = require 'events'

class SlurryStream extends EventEmitter
  destroy: =>
    throw new Error 'must override destroy'

module.exports = SlurryStream
