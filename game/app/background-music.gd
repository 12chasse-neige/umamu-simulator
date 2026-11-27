extends AudioStreamPlayer

const MUSIC := "res://design/music"
const FORMATS := ["ogg", "mp3", "wav"]
const RACE_FOLDER := "res://design/music/01-race"
const STINGERS_FOLDER := "res://design/music/06-stingers"
const AMBIENT_VOLUME_DB := -16.0
const RACE_VOLUME_DB := -8.0

enum RaceCue { ENTRY, START, RUN, RESULTS }

const RACE_TRACKS := {
	RaceCue.ENTRY: "res://design/music/02-bgm-am/1-05. am003 -Cleats, Powerfully and Lightly.mp3",
	RaceCue.START: RACE_FOLDER + "/8-01. 1001 cl#2 -Tokyo & Nakayama G1 Race.mp3",
	RaceCue.RUN: RACE_FOLDER + "/arc-race-bgm.mp3",
	RaceCue.RESULTS: RACE_FOLDER + "/8-10. 1010 cl#2 -Tokyo & Nakayama Open Race.mp3",
}
# The closing phrase of the 26-second fanfare fits the existing countdown.
const START_OFFSET := 19.5

var _remaining: Array[String] = []
var _unplayable: Dictionary[String, bool] = {}
var _last_track := ""
var _random := RandomNumberGenerator.new()
var _using_race_cue := false
var _ambient_stream: AudioStream
var _ambient_position := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	volume_db = AMBIENT_VOLUME_DB
	finished.connect(_on_finished)
	if DisplayServer.get_name() != "headless":
		_play_next()


func play_race_cue(cue: RaceCue) -> void:
	var path: String = RACE_TRACKS[cue]
	if not FileAccess.file_exists(path):
		resume_ambient()
		return
	var audio := AudioStreamMP3.load_from_file(path)
	if audio == null:
		resume_ambient()
		return
	if not _using_race_cue:
		_ambient_stream = stream if playing else null
		_ambient_position = get_playback_position()
	_using_race_cue = true
	volume_db = RACE_VOLUME_DB
	audio.loop = cue == RaceCue.ENTRY or cue == RaceCue.RUN
	stream = audio
	play(START_OFFSET if cue == RaceCue.START else 0.0)


func resume_ambient() -> void:
	if not _using_race_cue:
		return
	_using_race_cue = false
	stop()
	volume_db = AMBIENT_VOLUME_DB
	stream = _ambient_stream
	_ambient_stream = null
	if stream != null:
		play(_ambient_position)
	elif DisplayServer.get_name() != "headless":
		_play_next()


func _on_finished() -> void:
	if not _using_race_cue:
		_play_next()


func _play_next() -> void:
	if _remaining.is_empty():
		_collect(MUSIC)
	while not _remaining.is_empty():
		var index := _random.randi_range(0, _remaining.size() - 1)
		if _remaining.size() > 1 and _remaining[index] == _last_track:
			index = (index + 1) % _remaining.size()
		var source := _remaining.pop_at(index) as String
		if _play_file(source):
			return
		_unplayable[source] = true


func _collect(directory: String) -> void:
	if directory == RACE_FOLDER or directory == STINGERS_FOLDER:
		return
	for filename in DirAccess.get_files_at(directory):
		var source := directory.path_join(filename)
		if filename.get_extension().to_lower() in FORMATS and not _unplayable.has(source) and not RACE_TRACKS.values().has(source):
			_remaining.append(source)
	for subdirectory in DirAccess.get_directories_at(directory):
		_collect(directory.path_join(subdirectory))


func _play_file(source: String) -> bool:
	var audio: AudioStream
	match source.get_extension().to_lower():
		"ogg":
			audio = AudioStreamOggVorbis.load_from_file(source)
		"mp3":
			audio = AudioStreamMP3.load_from_file(source)
		"wav":
			audio = AudioStreamWAV.load_from_file(source)
	if audio == null:
		return false
	stream = audio
	_last_track = source
	play()
	return true
