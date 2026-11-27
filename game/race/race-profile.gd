extends RefCounted

# Five-star initial stats, running style grades (Front/Pace/Late/End), Turf/Dirt and Sprint.
# Source: umamusu.wiki trainee cards. Outfit slugs identify the local roster models.
const CARDS := {
	"admire-vega": [118, 96, 132, 85, 119, "GGBA", "AG", "F"],
	"agnes-digital": [104, 111, 101, 122, 112, "GAAB", "AA", "F"],
	"air-groove": [111, 105, 105, 112, 117, "DAAG", "AG", "C"],
	"calstone-light-o": [145, 70, 113, 114, 108, "ACGG", "AG", "A"],
	"daiwa-scarlet": [109, 99, 103, 122, 117, "AAEG", "AG", "F"],
	"el-condor-pasa": [110, 98, 103, 121, 118, "EAAC", "AB", "F"],
	"fenomeno": [92, 142, 92, 120, 104, "CAEG", "AG", "G"],
	"fuji-kiseki": [117, 107, 118, 100, 108, "CACG", "AF", "B"],
	"gold-ship": [106, 124, 129, 99, 92, "GBBA", "AG", "G"],
	"grass-wonder": [118, 91, 129, 96, 116, "FAAF", "AG", "G"],
	"hishi-akebono": [120, 74, 132, 111, 113, "BACG", "AF", "A"],
	"hishi-amazon": [113, 103, 129, 100, 105, "GBCA", "AE", "D"],
	"maruzensky": [118, 84, 105, 122, 121, "AEGG", "AD", "B"],
	"matikane-tanhauser": [103, 117, 106, 114, 110, "FAAE", "AG", "G"],
	"mayano-top-gun-halloween": [88, 138, 84, 124, 116, "AABB", "AE", "D"],
	"meisho-doto": [113, 116, 104, 118, 99, "FABE", "AE", "G"],
	"meisho-doto-halloween": [109, 109, 92, 126, 114, "FABE", "AE", "G"],
	"mejiro-mcqueen": [87, 136, 87, 125, 115, "BADF", "AE", "G"],
	"narita-brian": [113, 109, 122, 108, 98, "GAAD", "AG", "F"],
	"narita-top-road": [112, 124, 101, 112, 101, "FABD", "AG", "G"],
	"oguri-cap": [124, 81, 130, 103, 112, "FAAD", "AB", "E"],
	"satono-diamond": [111, 108, 113, 101, 117, "GBAD", "AG", "G"],
	"seiun-sky": [120, 120, 108, 101, 101, "ABDE", "AG", "G"],
	"silence-suzuka": [124, 102, 94, 122, 108, "ACEG", "AG", "D"],
	"special-week": [102, 108, 120, 110, 110, "GAAC", "AG", "F"],
	"still-in-love": [112, 109, 119, 110, 100, "GAAF", "AG", "C"],
	"super-creek": [84, 129, 92, 129, 116, "DABG", "AG", "G"],
	"super-creek-mummy": [90, 129, 92, 119, 120, "DABG", "AG", "G"],
	"symboli-rudolf": [106, 111, 101, 118, 114, "BAAC", "AG", "E"],
	"taiki-shuttle": [118, 87, 119, 113, 113, "CAEG", "AB", "A"],
	"tamamo-cross": [101, 116, 129, 102, 102, "GAAA", "AF", "G"],
	"tm-opera-o": [91, 132, 91, 125, 111, "CAAG", "AE", "G"],
	"tokai-teio": [109, 109, 102, 112, 118, "DACE", "AG", "F"],
	"twin-turbo": [137, 98, 107, 119, 89, "AGGG", "AF", "G"],
	"vodka": [124, 79, 136, 97, 114, "CBAF", "AG", "F"],
}

# Local Academy builds for runners without a trainee card. Named proxies and
# future models get a stable build independent of selection or starting gate.
const ACADEMY_BUILDS := [
	[122, 101, 112, 105, 110, "ABDC", "AB", "B"],
	[110, 119, 102, 109, 110, "BABC", "BA", "B"],
	[109, 104, 123, 110, 104, "DBAB", "AB", "B"],
	[112, 111, 105, 121, 101, "DCBA", "BA", "B"],
]

var speed: float
var stamina: float
var power: float
var guts: float
var wit: float
var styles: String
var surfaces: String
var sprint: String


func _init(path: String, title: String) -> void:
	var key := path.get_file().get_basename()
	if key == "special-week-trial":
		key = "special-week"
	var identity := title if key.is_empty() else key
	var stats: Array = CARDS.get(key, ACADEMY_BUILDS[identity.hash() % ACADEMY_BUILDS.size()])
	speed = stats[0]
	stamina = stats[1]
	power = stats[2]
	guts = stats[3]
	wit = stats[4]
	styles = stats[5]
	surfaces = stats[6]
	sprint = stats[7]


func preferred_style(field_styles: Array[int]) -> int:
	var best := 0
	for index in range(1, styles.length()):
		if styles[index] < styles[best] or (styles[index] == styles[best] and field_styles[index] < field_styles[best]):
			best = index
	return best
