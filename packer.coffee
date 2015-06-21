fs = require 'fs'
_ = require 'lodash'
midiConverter = require 'midi-converter'
slug = require 'slug'


# # # # #
# tools #
# ..... #
# # # # #

# bin utils
toBinArr = (value)->
  binstr = ("00000000" + (value).toString(2)).substr(-8,8)
  binarr = (parseInt v for v in binstr)

fromBinArr = (binarr)->
  binstr = ""
  for v in binarr
    binstr += v
  parseInt binstr, 2

# merge pitch frames of same time to fit with LSTM epochs
# there is a loss of data here
mergePitchFrames = (frames)->
  # result
  merged = []
  # get the last frame
  last_time =  _.last(frames).time
  # iterate 8 by 8
  ct = 0
  while ct <= last_time
    res = _.where frames, {time:ct}
    if res.length
      # create flat
      flat = [] # (0 for i in [0..(res[0].map.length-1)*3])
      # process each res
      _.each res, (d,i)->
        if i <= 3
          flat = flat.concat d.map
      while flat.length < 12
        flat.push 0

      merged.push flat
    ct += 2
  #console.log merged.length, frames.length
  return merged

# there is a loss of data here
mergeMaxFrames = (frames)->
  # result
  merged = []
  # get the last frame
  last_time =  _.last(frames).time
  # iterate 8 by 8
  ct = 0
  while ct <= last_time
    res = _.where frames, {time:ct}
    if res.length
      # takes the higher
      higher = toBinArr 0
      _.each res, (d)->
        #console.log fromBinArr(d.map), fromBinArr(higher)
        if fromBinArr(d.map) > fromBinArr(higher)
          higher = d.map
      merged.push higher
    ct += 2

  return merged

# process args
args = process.argv.slice 2
# get midi file path
midi_path = args[args.indexOf('-f')+1]
if !midi_path or midi_path[0] is '-' or !midi_path.split('.')[1].match /mid(i)?$/
  console.log "no midifile provided"
  process.exit 1

# put the file in json
jsonSong = midiConverter.midiToJson(fs.readFileSync(midi_path, 'binary'))

# get global infos
# tick per beat
ticksPerBeat = jsonSong.header.ticksPerBeat
ticksPerThirtySecond = ticksPerBeat/8

# get significant tracks
real_tracks = []
_.each jsonSong.tracks, (track)->
  # count node on and note off
  ons = _.where track, {subtype:'noteOn'}
  # no drums
  if ons[0] and ons[0].channel isnt 9
    real_tracks.push track if ons.length

# packed song
packed_song = []
# process the tracks
_.each real_tracks, (track, ti)->

  packed_track =
    offset: 0
    pitches: null
    durations: null
    velocities: null

  tcount = 0
  index = {}
  
  # here we store the pitches and durs as binary array
  # 24 bits
  pitch_bmap = []
  # 8 bits
  dur_bmap = []
  # 8 bits
  vel_bmap = []
  # process
  # manage first rest to sync the tracks
  firstOn = _.where track, {subtype:'noteOn'}
  if firstOn[0].deltaTime > 0
    packed_track.offset = firstOn[0].deltaTime/ticksPerThirtySecond

  _.each track, (evt, ei)->
    if evt.subtype is 'noteOn' or evt.subtype is 'noteOff'
      tcount += evt.deltaTime/ticksPerThirtySecond
      pitch = evt.noteNumber%12 + 1
      if evt.subtype is 'noteOn'
        index[pitch] = {vel: evt.velocity, ontime: tcount}
      if evt.subtype is 'noteOff'
        if index[pitch]
          time = Math.round index[pitch].ontime
          dur = Math.round(tcount - index[pitch].ontime)
          bindur = toBinArr dur
          binvel = toBinArr index[pitch].vel
          console.log dur, index[pitch].vel
          console.log bindur, binvel
          binpitch = toBinArr(pitch).slice(4,8)

          # push
          pitch_bmap.push {time:time, map:binpitch}
          dur_bmap.push {time:time, map:bindur}
          vel_bmap.push {time:time, map:binvel}
          # delete, noteOn/Off processed
          delete index[evt.noteNumber%24]

  pitch_bmap = _.sortBy pitch_bmap, (n)-> n.time
  dur_bmap = _.sortBy dur_bmap, (n)-> n.time
  vel_bmap = _.sortBy vel_bmap, (n)-> n.time
  packed_track.pitches = mergePitchFrames pitch_bmap
  packed_track.durations = mergeMaxFrames dur_bmap
  packed_track.velocities = mergeMaxFrames vel_bmap

  console.log packed_track.pitches.length, packed_track.durations.length, packed_track.velocities.length
  packed_song.push packed_track

# store the song info
name = slug _.first(_.last(midi_path.split('/')).split('.'))
song = {name:name, raw:packed_song}
fs.writeFileSync './data/pack/'+name+'.json', JSON.stringify(song, null, 2), 'utf8'
