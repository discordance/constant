# recompose from the many Lstm
#
#
fs = require 'fs'
_ = require 'lodash'
synaptic = require 'synaptic'
Network = synaptic.Network

class Recomposer

  chunkLength: 8

  loadsNets: (name)->
    net_json = fs.readFileSync 'data/net/'+name+'.json', 'utf8'
    nets = JSON.parse net_json
    return nets

  recompose: (nets, llength=128, lloop=0)->
    # each tracks types
    _.each nets, (track)=>
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
        ncursor = 0
        pitch_net = null
        dur_nel = null
        vel_net = null
        while ct < llength
          # console.log "iteration #{ct%@chunkLength}, in networks of chunk #{netc%chunks}"
          # pick pitch
          if netc%chunks isnt ncursor
            pitch_net = track.pitch[netc%chunks]
            pitch_net = Network.fromJSON(pitch_net)

          ncursor = netc%chunks
          ct++
          netc++ if !(ct%(@chunkLength))

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
  recomposer.recompose nets

