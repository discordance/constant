# recompose from the many Lstm
#
#
util = require 'util'
fs = require 'fs'
_ = require 'lodash'
synaptic = require 'synaptic'
Network = synaptic.Network

class Recomposer

  chunkLength: 8

  fromBinArr: (binarr)->
    binstr = ""
    for v in binarr
      binstr += v
    parseInt binstr, 2

  loadsNets: (name)->
    net_json = fs.readFileSync 'data/net/'+name+'.json', 'utf8'
    nets = JSON.parse net_json
    return nets

  recompose: (nets, llength=128, lloop=0)->
    # recomposed tracks
    retracks = []
    # each tracks types
    _.each nets, (track)=>
      # recomposed track events
      retrack = []
      # assert unique length
      un = [Object.keys(track.pitch).length, Object.keys(track.vel).length, Object.keys(track.dur).length]
      if _.uniq(un).length isnt 1
        console.log "skiping track, number of nets are not uniform ..."
      else
        console.log "assert uniform net lengths succeded ..."
        chunks = un[0]
        console.log "we have #{chunks} chunks in these networks ..."
        ct = 0
        netc = 0
        # pre compute the networks
        _.each track.pitch, (serial_net, i)->
          track.pitch[i] = (Network.fromJSON serial_net).standalone()
        _.each track.dur, (serial_net, i)->
          track.dur[i] = (Network.fromJSON serial_net).standalone()
        _.each track.vel, (serial_net, i)->
          track.vel[i] = (Network.fromJSON serial_net).standalone()
        console.log 'heap', (process.memoryUsage().heapUsed/process.memoryUsage().heapTotal)
        last_pitch = [0,0,0,0,0,0,0,0,0,0,0,0]
        last_dur = [0,0,0,0,0,0,0,0]
        last_vel = [0,0,0,0,0,0,0,0]

        while ct < llength
          last_pitch = _.map track.pitch[netc%chunks](last_pitch), (d)-> return Math.round d
          last_dur = _.map track.dur[netc%chunks](last_dur), (d)-> return Math.round d
          last_vel = _.map track.vel[netc%chunks](last_vel), (d)-> return Math.round d
          retrack.push [last_pitch, last_dur, last_vel]
          ct++
          netc++ if !(ct%(@chunkLength))
        retracks.push retrack
    return retracks

  midification: (retracks)->
    _.each retracks, (track, ti)->
      _.each track, (event, ei)->
        pitches = _.map _.chunk(event[0], 4), (arr)->
          return recomposer.fromBinArr arr
        pitches = _.filter pitches, (d)-> return d
        pitches = _.map pitches, (d)-> return d-1
        durs = recomposer.fromBinArr event[1]
        vels = recomposer.fromBinArr event[2]
        # console.log pitches, durs, vels
        console.log event




module.exports = Recomposer

# process args
#
args = process.argv.slice 2
# get midi file path
net_name = args[args.indexOf('-n')+1]
if net_name
  console.log 'we got', net_name
  recomposer = new Recomposer
  nets = recomposer.loadsNets net_name
  retracks = recomposer.recompose nets
  recomposer.midification retracks


