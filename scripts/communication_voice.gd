extends RefCounted
## Short cached electronic phonemes, following the existing impact WAV pattern.
## No TTS, sample assets or whole-sentence allocation during a frame.
const RATE := 16000
const CACHE_LIMIT := 64
static var _cache: Dictionary = {}

static func syllable(profile: Dictionary,variant: int = 0) -> AudioStreamWAV:
	var voice: Dictionary=profile.get("voice",{})
	var pitch:=float(voice.get("pitch",330.0))
	var timbre:=float(voice.get("timbre",.3))
	var key: String="%d/%d/%d" % [roundi(pitch),roundi(timbre*16),posmod(variant,4)]
	if _cache.has(key): return _cache[key]
	var duration:=.075+posmod(variant,3)*.012
	var count:=int(RATE*duration)
	var bytes:=PackedByteArray()
	bytes.resize(count*2)
	for i in range(count):
		var t:=i/float(RATE)
		var phase:=TAU*pitch*(1.0+posmod(variant,4)*.075)*t
		var envelope:=sin(PI*i/float(count))
		var value: float=(sin(phase)+sin(phase*2.01)*timbre*.35+sin(phase*.5)*.15)*envelope*.32
		bytes.encode_s16(i*2,clampi(int(value*32767),-32767,32767))
	var sound:=AudioStreamWAV.new()
	sound.format=AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate=RATE
	sound.stereo=false
	sound.data=bytes
	if _cache.size()>=CACHE_LIMIT: _cache.erase(_cache.keys()[0])
	_cache[key]=sound
	return sound
