{afterEach, beforeEach, describe, it} = global
{expect}     = require 'chai'
sinon        = require 'sinon'
SlurryStream = require '../../slurry-stream'

describe 'SlurryStream', ->
  beforeEach ->
    @slurryStream = new SlurryStream

  it 'should support `on`', ->
    expect(@slurryStream).to.exist

  it 'should throw an error for destroy', ->
    expect(-> @slurryStream.destroy).to.throw
