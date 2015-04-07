cluster = require 'cluster'
numCPUs = require('os').cpus().length
hub = require 'clusterhub'
fs = require 'fs'
_ = require 'lodash'
synaptic = require 'synaptic'
Trainer = synaptic.Trainer
Architect = synaptic.Architect

# # # # #
# tools #
# ..... #
# # # # #

# make training set
toTrainSet = (frag)->
  trainingSet = []
  _.each frag, (d,i)->
    if frag[i+1]
      trainingSet.push {
        input: frag[i],
        output: frag[i+1]
      }
  return trainingSet

# process args
args = process.argv.slice 2
# get midi file path
song_name = args[args.indexOf('-n')+1]
if !song_name or song_name[0] is '-'
  console.log "no song name provided"
  process.exit 1

# load file
song_json = fs.readFileSync('./data/'+song_name+'.json', 'utf8')
song = JSON.parse song_json
num_tracks = song.raw.length

# machine learning options
opts =
  rate: .008
  iterations: 50000
  error: .005
  shuffle: false
  #cost: Trainer.cost.CROSS_ENTROPY
  cost: Trainer.cost.MSE

# chunk size -> how much training chunks to use
chunk_size = 8

if cluster.isMaster
  # count dones
  hub.set 'dones', 0, ->
    hub.set 'networks', {}, ->
      # Fork workers.
      i = 0
      while i < numCPUs/2
        cluster.fork()
        i++
      # exit event
      cluster.on 'exit', (worker, code, signal) ->
        console.log 'worker ' + worker.process.pid + ' died'
        return

      hub.on 'finish', (data) ->
        console.log "finish !"
        hub.get 'networks', (value)->
          console.log value
else

  id = cluster.worker.id-1
  track = song.raw[id]
  if track
    # chunk it to learnable fragments
    pitch_frags = _.chunk track.pitches, chunk_size
    dur_frags = _.chunk track.pitches, chunk_size
    vel_frags = _.chunk track.pitches, chunk_size

    # learn pitches
    # pitch_nets = []
    # _.each pitch_frags, (frag, i)->
    #   train = toTrainSet frag
    #   pitch_net = new Architect.LSTM(24,48,24)
    #   opts.customLog =
    #     every: 10
    #     do: (err)->
    #       console.log "Thread:", id+1, "- Pitch frag:", i+1, "iteration:", err.iterations, " err:", err.error
    #   trainer = new Trainer pitch_net
    #   console.log "Start to train -> Thread:", id+1, "- Pitch frag:", i+1
    #   trainer.train train, opts
    #   pitch_nets.push pitch_net.toJSON()

    # learn durs
    dur_nets = []
    _.each dur_frags, (frag, i)->
      train = toTrainSet frag
      dur_net = new Architect.LSTM(8,8,8,8,8)
      opts.customLog =
        every: 250
        do: (err)->
          console.log "Thread:", id+1, "- Duration frag:", i+1, "iteration:", err.iterations, " err:", err.error
      trainer = new Trainer dur_net
      console.log "Start to train -> Thread:", id+1, "- Duration frag:", i+1
      trainer.train train, opts
      dur_nets.push dur_net.toJSON()

    # learn vels
    vel_nets = []
    _.each vel_frags, (frag, i)->
      train = toTrainSet frag
      vel_net = new Architect.LSTM(8,8,8,8,8)
      opts.customLog =
        every: 250
        do: (err)->
          console.log "Thread:", id+1, "- Velocity frag:", i+1, "iteration:", err.iterations, " err:", err.error
      trainer = new Trainer vel_net
      console.log "Start to train -> Thread:", id+1, "- Velocity frag:", i+1
      trainer.train train, opts
      vel_nets.push vel_net.toJSON()

    hub.incr 'dones', (val) ->
      # save tracks nets
      hub.get 'networks', (value)->
        value[id] = {
          dur_nets: dur_nets,
          vel_nets: vel_nets
        }
        hub.set 'networks', value, ->
          if val is num_tracks
            hub.emitRemote 'finish'
          process.exit 0


      #console.log train
    #console.log pitch_frags.length, dur_frags.length, vel_frags.length

    # something to eat
    # pitch_net = new Architect.LSTM(24,24,24,24)
    # dur_net = new Architect.LSTM(8,8,8,8)
    # vel_net = new Architect.LSTM(8,8,8,8)

  # hub.on 'song', (data) ->
  #   console.log data
