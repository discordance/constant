fs = require 'fs'
_ = require 'lodash'
midiConverter = require 'midi-converter'

#tools
toBinArr = (value)->
  binstr = ("00000000" + (value).toString(2)).substr(-8,8)
  binarr = (parseInt v for v in binstr)

fromBinArr = (binarr)->
  binstr = ""
  for v in binarr
    binstr += v
  parseInt binstr, 2


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
  real_tracks.push track if ons.length

# what is the longest track
max_tick = []
_.each real_tracks, (track, ti)->
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
  _.each track, (evt, ei)->
    if evt.subtype is 'noteOn' or evt.subtype is 'noteOff'
      tcount += evt.deltaTime/ticksPerThirtySecond
      pitch = evt.noteNumber%24
      if evt.subtype is 'noteOn'
        index[pitch] = {vel: evt.velocity, ontime: tcount}
      if evt.subtype is 'noteOff'
        if index[pitch]
          time = index[pitch].ontime
          dur = tcount - index[pitch].ontime
          bindur = toBinArr dur
          binvel = toBinArr index[pitch].vel
          binpitch = (0 for [0..23])
          binpitch[pitch] = 1

          # push
          pitch_bmap.push {time:time, map:binpitch}
          dur_bmap.push {time:time, map:bindur}
          vel_bmap.push {time:time, map:binvel}
          # delete, noteOn/Off processed
          delete index[evt.noteNumber%24]


  console.log(pitch_bmap) if ti < 1
