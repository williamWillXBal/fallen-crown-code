# ============================================
# SETTINGS.GD — Autoload singleton pour tous les réglages du jeu
# ============================================
# FONCTIONS (cherche par Ctrl+F sur le nom) :
#   _ready()              → Charge les settings depuis user://settings.cfg au démarrage
#   get_value(key, default) → Lit une valeur, retourne default si absente
#   set_value(key, value)   → Écrit une valeur + sauvegarde auto
#   reset()               → Remet toutes les valeurs aux défauts
#   _load()               → Charge le fichier de config (appelé au _ready)
#   _save()               → Sauvegarde sur disque (appelé à chaque set_value)
#
# CONSTANTES / REFS IMPORTANTES :
#   CONFIG_PATH           → user://settings.cfg (chemin sauvegarde)
#   DEFAULTS              → Dictionnaire des valeurs par défaut (facile à étendre)
#   data                  → Dictionnaire en mémoire des valeurs actuelles
#   setting_changed       → Signal émis quand une valeur change (clé, nouvelle_valeur)
#
# POUR AJOUTER UNE NOUVELLE OPTION :
#   1. Ajoute une clé dans DEFAULTS (ex: "vol_sfx": 0.8)
#   2. Dans hud.gd _build_settings_panel(), ajoute _add_slider(...) ou _add_checkbox(...)
#   3. Dans le code qui doit utiliser la valeur, fais Settings.get_value("vol_sfx", 0.8)
#   C'est tout. Pas besoin de toucher à ce fichier autre que DEFAULTS.
# ============================================

extends Node

signal setting_changed(key: String, value)

const CONFIG_PATH := "user://settings.cfg"

# Toutes les valeurs par défaut du jeu — étends ce dict pour ajouter des options
const DEFAULTS := {
	# Caméra
	"cam_sens_h": 0.005,   # Sensibilité horizontale (touch)
	"cam_sens_v": 0.005,   # Sensibilité verticale (touch)
	# Futures options (exemples, décommente quand tu en as besoin)
	# "cam_invert_y": false,
	# "cam_fov": 75.0,
	# "vol_sfx": 0.8,
	# "vol_music": 0.5,
	# "haptic_feedback": true,
}

var data: Dictionary = {}

func _ready():
	_load()

func get_value(key: String, default_value = null):
	if data.has(key):
		return data[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return default_value

func set_value(key: String, value) -> void:
	data[key] = value
	_save()
	setting_changed.emit(key, value)

func reset() -> void:
	data = DEFAULTS.duplicate(true)
	_save()
	for k in data.keys():
		setting_changed.emit(k, data[k])

func _load() -> void:
	# Initialise avec les défauts
	data = DEFAULTS.duplicate(true)
	# Tente de charger le fichier existant
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return  # Pas de fichier, on garde les défauts
	for k in DEFAULTS.keys():
		if cfg.has_section_key("settings", k):
			data[k] = cfg.get_value("settings", k)

func _save() -> void:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("settings", k, data[k])
	cfg.save(CONFIG_PATH)
