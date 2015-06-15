# rewrite learner
fs = require 'fs'
_ = require 'lodash'
synaptic = require 'synaptic'
Trainer = synaptic.Trainer
Architect = synaptic.Architect
numCPUs = require('os').cpus().length-1
Worker = require('webworker-threads').Worker


class LearnerThreaded

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



  buildTasks: (song_name)->
    # load file
    song_json = fs.readFileSync('./data/pack/'+song_name+'.json', 'utf8')
    song = JSON.parse song_json
    num_tracks = song.raw.length
    tracks_net = ({pitch:{}, dur:{}, vel:{}} for i in [0..song.raw.length-1])
    tasks = []
    ids = 0
    console.log "Start the tasks ..."
    # create tasks
    _.each song.raw, (track, track_num) =>
      # chunk it to learnable fragments
      pitch_frags = _.chunk track.pitches, @chunk_size
      dur_frags = _.chunk track.pitches, @chunk_size
      vel_frags = _.chunk track.pitches, @chunk_size

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
      console.log Float64Array
      # import synaptic lib in the worker
      synaptic_code = native_fs_.readFileSync 'workerlib/synaptic.min.js'
      eval synaptic_code
      Trainer = synaptic.Trainer
      Architect = synaptic.Architect
      
      # options config
      # machine learning options
      @opts =
        rate: .008
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
            every: 250
            do: (err)->
              console.log "Thread:",\
              tid,\
              "Track: #{task.track} - Pitch frag:",\
              task.frag+1,\
              "iteration:",\
              err.iterations,\
              " err:", err.error
        # pitch
        if task.type is 'dur'
          net = new Architect.LSTM(8,8,8,8)
          opts.schedule =
            every: 250
            do: (err)->
              console.log "Thread:",\
              tid,\
              "Track: #{task.track} - Duration frag:",\
              task.frag+1,\
              "iteration:",\
              err.iterations, " err:", err.error
        # vel
        if task.type is 'vel'
          net = new Architect.LSTM(8,8,8,8)
          opts.schedule =
            every: 250
            do: (err)->
              console.log "Thread:",\
              tid,\
              "Track: #{task.track} - Velocity frag:",\
              task.frag+1,\
              "iteration:",\
              err.iterations,\
              " err:", err.error

        trainer = new Trainer net
        console.log "Start to train -> Thread:",\
        tid,\
        "Track: #{task.track} - #{task.type} frag:",\
        task.frag+1

        trainer.train task.train_set, opts
        callback net
        
      @onmessage = (message)->
        if message.data.type is 'task'
          try
            @work @opts, message.data.task, self.thread.id, (net)->
              console.log net
          catch err
            console.log err.message
        if message.data.type is 'end'
          self.close()
      
    # build workers
    workers = []
    for i in [0..numCPUs-1]
      worker = new Worker template
      task = tasks.shift()
      worker.postMessage {type:'task', task: task}
      workers.push worker


learner = new LearnerThreaded()
tasks = learner.buildTasks "china"
learner.launchThreads tasks





