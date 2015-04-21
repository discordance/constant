cluster = require 'cluster'
numCPUs = require('os').cpus().length-2
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
  # Fork workers.
  i = 0
  while i < numCPUs
    cluster.fork()
    i++
  # prepare pile of tasks
  # empty tasks
  hub.set 'tasks', [], ->
    # results, classified by type and by frag order
    hub.set 'networks', {pitch:{}, dur:{}, vel:{}}, ->
      # exit event, likely to happen progressively
      cluster.on 'exit', (worker, code, signal) ->
        console.log 'worker ' + worker.process.pid + ' died'
        return

      tasks = []
      ids = 0
      console.log "Start the tasks ..."
      # create tasks
      _.each song.raw, (track, i) ->
        # chunk it to learnable fragments
        pitch_frags = _.chunk track.pitches, chunk_size
        dur_frags = _.chunk track.pitches, chunk_size
        vel_frags = _.chunk track.pitches, chunk_size

        # interleave
        for ii in [0..pitch_frags.length-1]
          if ii
            pitch_frags[ii].unshift _.last pitch_frags[ii-1]
        for ii in [0..dur_frags.length-1]
          if ii
            dur_frags[ii].unshift _.last dur_frags[ii-1]
        for ii in [0..vel_frags.length-1]
          if ii
            vel_frags[ii].unshift _.last vel_frags[ii-1]

        # a task per pitch frag
        _.each pitch_frags, (frag, i)->
          task = {frag:i, type:'pitch', id:ids}
          task.train_set = toTrainSet frag
          tasks.push task
          ids++

        _.each dur_frags, (frag, i)->
          task = {frag:i, type:'dur', id:ids}
          task.train_set = toTrainSet frag
          tasks.push task
          ids++

        _.each vel_frags, (frag, i)->
          task = {frag:i, type:'vel', id:ids}
          task.train_set = toTrainSet frag
          task.net = new Architect.LSTM(8,8,8,8)
          tasks.push task
          ids++

      console.log "Created #{tasks.length} tasks, launching #{numCPUs} threads on it"
      hub.set 'tasks', tasks, ->
        # thread say he is free, give him a task
        hub.on 'task_free', (data)->
          console.log "#{data.id} is free"
          if data.result
            console.log "store the processed result"
            hub.get 'networks', (nets)->
              nets[data.task.type][data.task.frag] = data.result
              hub.set 'networks', nets, ->
                hub.get 'tasks', (tasks) ->
                  # finished
                  if !tasks.length
                    console.log 'finished'
                    fs.writeFileSync './data/'+song_name+'_nets.json', JSON.stringify(nets, null, 2), 'utf8'
                  task = tasks.shift()
                  hub.set 'tasks', tasks, ->
                    hub.emitRemote 'task', {id:data.id, task:task}
          else
            # give him some new job
            hub.get 'tasks', (tasks) ->
              task = tasks.shift()
              hub.set 'tasks', tasks, ->
                hub.emitRemote 'task', {id:data.id, task:task}

else

  id = cluster.worker.id-1
  free = true

  hub.emitRemote 'task_free', {id:id}

  hub.on 'task', (data)->
    # check if its for me
    if data.id is id
      if free
        free = false
        net = null
        # pitch
        if data.task.type is 'pitch'
          net = new Architect.LSTM(12,12,12,12)
          opts.customLog =
            every: 250
            do: (err)->
              console.log "Thread:", id+1, "- Pitch frag:", data.task.frag+1, "iteration:", err.iterations, " err:", err.error
        # pitch
        if data.task.type is 'dur'
          net = new Architect.LSTM(8,8,8,8)
          opts.customLog =
            every: 250
            do: (err)->
              console.log "Thread:", id+1, "- Duration frag:", data.task.frag+1, "iteration:", err.iterations, " err:", err.error
        # vel
        if data.task.type is 'vel'
          net = new Architect.LSTM(8,8,8,8)
          opts.customLog =
            every: 250
            do: (err)->
              console.log "Thread:", id+1, "- Velocity frag:", data.task.frag+1, "iteration:", err.iterations, " err:", err.error

        trainer = new Trainer net
        console.log "Start to train -> Thread:", id+1, "- #{data.task.type} frag:", data.task.frag+1
        trainer.train data.task.train_set, opts

        free = true
        hub.emitRemote 'task_free', {id:id, task: data.task, result: net.toJSON()}
        console.log "FREEE SA RACE"
