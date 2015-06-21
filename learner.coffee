# rewrite learner
fs = require 'fs'
_ = require 'lodash'
synaptic = require 'synaptic'
Trainer = synaptic.Trainer
Architect = synaptic.Architect
numCPUs = Math.ceil(require('os').cpus().length/2)
Worker = require('webworker-threads').Worker


class LearnerThreaded
  # main function
  run: (song_name, callback)->
    @callback = callback
    tasks = @buildTasks song_name
    @launchThreads tasks

  chunk_size: 8
  # make training set
  toTrainSet: (frag)->
    trainingSet = []
    _.each frag, (d,i)->
      if frag[i+1]
        trainingSet.push {
          input: frag[i],
          output: frag[i+1]
        }
    return trainingSet

  finish: (workers)->
    if !Object.keys(workers).length
      console.log "finishing", @song_name
      fs.writeFileSync './data/net/'+@song_name+'.json', JSON.stringify(@nets, null, 2), 'utf8'
      if @callback
        @callback()

  buildTasks: (song_name)->
    # load file
    song_json = fs.readFileSync('./data/pack/'+song_name+'.json', 'utf8')
    song = JSON.parse song_json
    num_tracks = song.raw.length
    @nets = ({pitch:{}, dur:{}, vel:{}} for i in [0..song.raw.length-1])
    @song_name = song_name
    tasks = []
    ids = 0
    console.log "Start the tasks ..."
    # create tasks
    _.each song.raw, (track, track_num) =>
      # chunk it to learnable fragments
      pitch_frags = _.chunk track.pitches, @chunk_size
      dur_frags = _.chunk track.durations, @chunk_size
      vel_frags = _.chunk track.velocities, @chunk_size
      console.log vel_frags, "VEL FRAG"

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
      _.each pitch_frags, (frag, i)=>
        task = {track: track_num, frag:i, type:'pitch', id:ids}
        task.train_set = @toTrainSet frag
        tasks.push task
        ids++

      _.each dur_frags, (frag, i)=>
        task = {track: track_num, frag:i, type:'dur', id:ids}
        task.train_set = @toTrainSet frag
        tasks.push task
        ids++

      _.each vel_frags, (frag, i)=>
        task = {track: track_num, frag:i, type:'vel', id:ids}
        task.train_set = @toTrainSet frag
        tasks.push task
        ids++

    console.log "Created #{tasks.length} tasks, can use #{numCPUs} threads on it"
    return tasks
  
  launchThreads: (tasks)->
    template = ()->
      # typed array shims
      importScripts 'workerlib/typedarray.js'
      self.Float64Array = Array#typedarray.Float64Array
      # import synaptic lib in the worker
      importScripts 'workerlib/synaptic.min.js'
      Trainer = synaptic.Trainer
      Architect = synaptic.Architect
      # options config
      # machine learning options
      @opts =
        rate: .01
        iterations: 30000
        error: .005
        shuffle: false
        #cost: Trainer.cost.CROSS_ENTROPY
        cost: Trainer.cost.MSE

      # the worker function that will train lstm
      @work = (opts, task, tid, callback)->
        net = null
        # pitch
        if task.type is 'pitch'
          net = new Architect.LSTM(12,12,12,12)
          opts.schedule =
            every: 100
            do: (err)->
              console.log "Thread: "+tid+" Track: #{task.track} - Pitch frag: "+task.frag+" iteration: "+err.iterations+" err: "+err.error
        # pitch
        if task.type is 'dur'
          net = new Architect.LSTM(8,8,8,8)
          opts.schedule =
            every: 100
            do: (err)->
              console.log "Thread: "+tid+" Track: #{task.track} - Duration frag: "+task.frag+" iteration: "+err.iterations+" err: "+ err.error
        # vel
        if task.type is 'vel'
          net = new Architect.LSTM(8,8,8,8)
          opts.schedule =
            every: 100
            do: (err)->
              console.log "Thread: "+tid+" Track: #{task.track} - Velocity frag: "+ task.frag+ " iteration: "+err.iterations+" err: "+err.error

        trainer = new Trainer net
        console.log "Start to train -> Thread: "+tid+" Track: #{task.track} - #{task.type} frag: "+task.frag

        trainer.train task.train_set, opts
        callback net
        
      @onmessage = (message)->
        if message.data.type is 'task'
          try
            @work @opts, message.data.task, self.thread.id, (net)->
              postMessage {net: net.toJSON(), task: message.data.task}
          catch err
            console.log err.message
        if message.data.type is 'end'
          self.close()
      
    # build workers
    workers = {}
    for i in [0..numCPUs-1]
      worker = new Worker template
      workers[worker.thread.id] = worker
    _.each workers, (worker)=>
      worker.onmessage = (message)=>
        @nets[message.data.task.track][message.data.task.type][message.data.task.frag] = message.data.net
        next_task = tasks.shift()
        if next_task
          worker.postMessage {type:'task', task: next_task}
        else
          delete workers[worker.thread.id]
          @finish workers
          worker.terminate()

      next_task = tasks.shift()
      worker.postMessage {type:'task', task: next_task}
     
    # worker.postMessage {type:'task', task: task}



module.exports = LearnerThreaded
# process args
#
args = process.argv.slice 2
# get midi file path
song_name = args[args.indexOf('-n')+1]
if song_name
  console.log 'we got', song_name
  learner = new LearnerThreaded()
  learner.run song_name, ()->
    console.log 'finished properly'



