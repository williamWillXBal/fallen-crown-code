# ============================================
# PLAYER.GD — Joueur FPS mobile avec arbalète voxel et combat
# ============================================
# FONCTIONS (cherche par Ctrl+F sur le nom) :
#   _ready()                           → Init (caméra, arbalète, sons, raycast)
#   _cube(parent, pos, size, mat)      → Helper : crée un cube mesh
#   _mat(color, r, m)                  → Helper : material standard
#   build_arms()                       → Construit l'arbalète voxel FPS
#   _input(event)                      → Inputs clavier (dev) : ZQSD + souris
#   _unhandled_input(event)            → Inputs tactiles : joysticks + attaque + saut
#   _physics_process(delta)            → Boucle physique (gravité, mouvement)
#   do_atk()                           → Attaque mêlée (épée) — appelée via WeaponController
#   get_dmg() -> int                   → Calcule dégâts mêlée selon combo
#   do_shoot()                         → Tir arbalète — appelée via WeaponController
#   set_weapon_sound(stream, db)       → Change le son d'arme (appelé par WeaponController au switch)
#   spawn_bolt(end_pos, target, local) → Carreau voxel qui vole puis reste planté
#   spawn_impact(pos)                  → Effet particules impact sur surface
#   harvest(obj, type)                 → Récolte ressource (arbre/pierre/fer)
#   take_damage(amount)                → Recevoir dégâts, vignette rouge HUD
#   _check_loot_pickup(delta)          → Détecte + attire + ramasse cubes de loot
#   _start_loot_magnet(cube)           → Lance tween d'attraction vers le player
#   _check_craft_stations()            → Détecte table de craft + affiche prompt HUD
#
# CONSTANTES / REFS IMPORTANTES :
#   speed (5.0)                        → Vitesse déplacement
#   mouse_sens / touch_sens            → Sensibilité caméra (fallback, lu via Settings)
#   Settings.get_value("cam_sens_h/v") → Valeur vivante lue à chaque event souris/touch
#   gravity_force (15.0)               → Force gravité
#   hp (100) / max_hp                  → Points de vie
#   inventory {wood, stone, iron, gold} → Ressources récoltées (mise à jour : +gold)
#   LOOT_TYPE_TO_INV                   → Map "fer"→"iron" etc. pour pickup loot
#   LOOT_PICKUP_RADIUS (1.8)           → Rayon de détection des cubes de loot
#   LOOT_MAGNET_DURATION (0.35)        → Durée tween d'attraction
#   has_xbow (true)                    → Arbalète équipée (compat legacy, vrai check = weapon_inventory)
#   xbow_dmg (25) / xbow_range (40)    → Valeurs FALLBACK — stats vraies lues depuis WeaponData
#   xbow_cd (1.2)                      → Valeur FALLBACK — cooldown géré par WeaponController
#   weapon_controller                  → Node enfant : dispatcher d'attaque selon arme active
#   weapon_inventory                   → Node enfant : liste des armes équipées
#   shoot_ray                          → RayCast3D pour détection cible
#   shoot_sfx                          → AudioStreamPlayer son de tir
#   move_tid / look_tid                → IDs tactiles joysticks gauche/droit
# ============================================

extends CharacterBody3D
@export var speed := 5.0
@export var mouse_sens := 0.003
@export var touch_sens := 0.005
@export var gravity_force := 15.0

var cam_pitch := 0.0
var hp := 100
var max_hp := 100
var inventory := {"wood": 0, "stone": 0, "iron": 0, "gold": 0}
# Mapping des noms de loot (FR, posés par enemy.gd) vers les clés inventory (EN)
const LOOT_TYPE_TO_INV := {
	"fer":    "iron",
	"bois":   "wood",
	"or":     "gold",
	"pierre": "stone",
}
# Pickup de loot : rayon de détection autour du player + durée du magnétisme
const LOOT_PICKUP_RADIUS := 1.8
const LOOT_MAGNET_DURATION := 0.35
# Détection des tables de craft : rayon dans lequel le prompt apparaît
const CRAFT_DETECTION_RADIUS := 2.5
# Noms affichés pour chaque type de table (clé = meta craft_type)
const CRAFT_STATION_NAMES := {
	"forge":          "Forge",
	"crossbow_bench": "Arbalétrier",
	"workbench":      "Établi",
	"tannery":        "Tannerie",
	"altar":          "Autel",
}
var tier := 0
var player_class := -1
var atk_cd := 0.0
var combo := 0
var combo_t := 0.0
var kills := 0
# Crossbow
var has_xbow := true
var xbow_dmg := 25
var xbow_range := 40.0
var xbow_cd := 1.2
var xbow_cd_timer := 0.0
var shoot_ray: RayCast3D

var move_tid := -1
var look_tid := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO
var fps_arms: Node3D
# === SPRINT ===
# sprint_factor varie entre 1.0 (marche) et 1.6 (sprint).
# Détection : joystick poussé à >85% → ramp vers 1.6, sinon ramp vers 1.0.
var sprint_factor := 1.0
var is_sprinting := false       # état latched pour éviter le flip-flop
var bob_phase_fast := 0.0       # accumulateur phase pour freq verticale (8 rad/s)
var bob_phase_slow := 0.0       # accumulateur phase pour freq horizontale (4 rad/s)
const SPRINT_TARGET := 1.2      # multiplicateur vitesse en sprint
const SPRINT_ENTER := 0.85      # seuil pour entrer en sprint
const SPRINT_EXIT := 0.65       # seuil pour sortir du sprint (hystérésis)
const SPRINT_DIP := -0.08       # rotation X de l'arme en sprint (subtil)
# === MODE INSPECT (DEBUG VISUEL) ===
# Si true, build_arms() affiche juste 3 cubes côte à côte devant la caméra
# (biceps, avant-bras, main droite) à leur taille réelle pour comprendre les
# proportions. Pas de rig, pas d'arme, pas de bras gauche. Mets à false pour
# revenir au rig FPS complet.
const INSPECT_MODE := false
# === MODE INSPECT ANGLES (sous-mode de INSPECT_MODE) ===
# Si false : 3 cubes côte à côte sans rotation (voir les TAILLES)
# Si true  : 1 bras articulé devant la caméra avec les angles appliqués
#            (voir l'effet de ARM_PIVOT_YAW + FOREARM_X_ROT + FOREARM_Z_ROT en isolé)
const INSPECT_ANGLES := false
# === MODE INSPECT WORLD (cubes flottants dans le monde) ===
# Si true, spawn 3 cubes flottants devant le spawn du joueur, à la même échelle
# que les bras du rig FPS (BICEPS_SIZE, FOREARM_SIZE, HAND_SIZE).
# Indépendant de INSPECT_MODE — les 2 peuvent être true en même temps.
# Le joueur peut tourner autour avec son perso pour screenshoter sous tous les
# angles, puis dessiner la pose voulue des bras par-dessus les screenshots.
const INSPECT_WORLD := true
# === TAILLES DES MEMBRES — partagées entre mode inspect ET rig FPS ===
# Modifie ICI une valeur → elle s'applique automatiquement aux 2 modes.
# Workflow : 1) ajuster en INSPECT_MODE pour voir les pièces isolées,
#            2) basculer INSPECT_MODE = false pour voir le rig assemblé.
const BICEPS_SIZE  := Vector3(0.16, 0.14, 0.28)  # X largeur, Y hauteur, Z profondeur
const FOREARM_SIZE := Vector3(0.16, 0.30, 0.14)  # avant-bras MÊME ÉPAISSEUR que le biceps, long en Y
const HAND_SIZE    := Vector3(0.16, 0.10, 0.18)  # main gantée
# === RÉGLAGES DU BRAS — modifie ICI dans Acode ===
# Pas d'Inspector, pas de slider — juste ces 6 chiffres à changer dans le code.
# Workflow : modifie un chiffre → save → lance le jeu → vois → re-modifie si pas bon.
# Plage utile pour chaque chiffre :
#   ARM_PIVOT_YAW   : -1.5 (très à droite) à 1.5 (très à gauche)
#   ARM_PIVOT_X     :  0.0 à 0.6  (pousse le bras à droite si +)
#   ARM_PIVOT_Y     : -0.6 à -0.1 (descend le bras si plus négatif)
#   ARM_PIVOT_Z     : -0.4 à -0.05 (rapproche le bras si plus négatif)
#   FOREARM_X_ROT   : -1.0 à 1.0  (avant-bras hoche OUI si +)
#   FOREARM_Z_ROT   : -1.0 à 1.0  (avant-bras penche BOF, négatif = vers centre)
const ARM_PIVOT_YAW   := 0.15    # rotation Y du pivot (le bras droit vire légèrement vers l'intérieur)
const ARM_PIVOT_X     := 0.35    # position X du pivot (gauche/droite)
const ARM_PIVOT_Y     := -0.32   # position Y du pivot (haut/bas)
const ARM_PIVOT_Z     := -0.18   # position Z du pivot (loin/proche caméra)
const FOREARM_X_ROT   := -0.2    # rotation X avant-bras (penche vers l'avant — main vers la caméra)
const FOREARM_Z_ROT   := -0.2    # rotation Z avant-bras (penche vers le centre — pose "tenir à 2 mains")
# === BRAS GAUCHE (indépendant du droit, n'affecte pas l'arme) ===
const ARM_L_PIVOT_YAW := -0.15   # rotation Y bras gauche (vire vers l'intérieur, mirror du droit)
const ARM_L_PIVOT_X   := -0.30   # position X (réduit de -0.55 → -0.30 : épaule visible sur mobile)
const ARM_L_PIVOT_Y   := -0.32   # position Y
const ARM_L_PIVOT_Z   := -0.18   # position Z
const FOREARM_L_X_ROT := -0.2    # rotation X avant-bras gauche (penche vers l'avant aussi)
const FOREARM_L_Z_ROT := 0.2     # rotation Z avant-bras gauche (penche vers le centre, mirror du droit)
# Membres pour références persistantes
var arm_r_pivot_ref: Node3D
var forearm_x_ref: Node3D        # pivot avant-bras (Node3D au coude pour rotation propre)
var hand_pivot_ref: Node3D       # pivot main FPS pour rotation H_X / H_Z (poignet)
var shoulder_r_cube_ref: MeshInstance3D  # cube épaule droite visible (armor)
var shoulder_l_cube_ref: MeshInstance3D  # cube épaule gauche visible (armor)
var arm_l_pivot_ref: Node3D
var forearm_s_ref: Node3D
var forearm_l_ref: Node3D        # pivot coude gauche (Node3D, pour rotation propre)
var hand_l_pivot_ref: Node3D     # pivot main gauche (poignet)
# Modèle 3D du joueur dans le monde (visible en TPS, caché en FPS).
# Contrairement à fps_arms qui est dans la caméra (donc invisible de l'extérieur),
# player_body est attaché au CharacterBody3D — il a un vrai corps dans le monde.
var player_body: Node3D
var xbow_model: Node3D   # Modèle 3D de l'arbalète (enfant de fps_arms, toggle au switch)
var sword_model: Node3D  # Modèle 3D de l'épée (enfant de fps_arms, toggle au switch)
var sword_pivot: Node3D  # Pivot interne placé à la poignée — tourné pendant l'anim de swing
var atk_anim := 0.0
var xbow_recoil := 0.0
# === WEAPON SWAY (lag de l'arme quand la caméra tourne) ===
# Track les deltas de rotation de la caméra entre frames pour appliquer un retard
# visuel sur l'arme. Quand tu tournes vite à droite, l'arme dérape à gauche puis
# rattrape. C'est LE détail qui fait le feel "AAA" dans CODM/BF/TaCZ.
var sway_yaw_vel := 0.0      # Vitesse de sway accumulée (yaw, gauche/droite)
var sway_pitch_vel := 0.0    # Vitesse de sway accumulée (pitch, haut/bas)
var prev_yaw := 0.0          # rotation.y du frame précédent
var prev_pitch := 0.0        # cam_pitch du frame précédent
# Système de combos épée : 3 styles qui alternent à chaque tap.
# Reset à 0 si on tape pas pendant sword_combo_reset_time secondes.
var sword_swing := 0.0           # Progression de l'anim en cours : 1.0 → 0
var sword_combo_index := 1       # 1 = Katana Flick par défaut (tap simple)
								 # 0 = Conan, 2 = Overhead, 3 = Uppercut (codés mais inutilisés
								 # pour l'instant — seront branchés via 2 boutons / direction caméra)
var sword_combo_timer := 0.0     # Temps depuis dernière attaque (reset à 0 si écoulé)
const SWORD_COMBO_RESET := 1.5   # Après 1.5s sans attaque, combo reset à 0
var shoot_sfx: AudioStreamPlayer

# === SYSTÈME D'ARMES (nouveau) ===
# Nodes enfants créés dans _ready(). Le WeaponController dispatche les attaques
# selon le type de l'arme active. L'Inventory gère les slots d'armes équipées.
# Le HUD appelle maintenant weapon_controller.try_attack() au lieu de do_shoot().
var weapon_controller: Node
var weapon_inventory: Node

# === MODE INSPECT WORLD : variables live ajustables via panneau in-game ===
# Ces valeurs initialisent depuis les const, puis les boutons +/- du panneau
# les modifient en live et update le bras du monde instantanément.
# 9 contrôles : épaule (YAW + X + Z) + avant-bras (YAW + X + Z) + main (YAW + X + Z) = bras complet.
# Les variables existent en double : live_* (bras DROIT) et live_l_* (bras GAUCHE).
# Le toggle SIDE détermine lequel les boutons +/- modifient.
var editing_side: String = "R"     # "R" = édite bras droit, "L" = édite bras gauche
# Bras DROIT (R) — Valeurs initiales = pose ÉPÉE finalisée (screenshot 2026-04-26)
var live_yaw: float = 0.15
var live_spread: float = 0.45      # SPRD
var live_sh_x_rot: float = 0.10
var live_sh_z_rot: float = 0.0
var live_f_yaw: float = 0.20
var live_x_rot: float = 1.50
var live_z_rot: float = 0.15
var live_h_yaw: float = 0.0
var live_hand_x_rot: float = -1.55
var live_hand_z_rot: float = 0.0
# Bras GAUCHE (L) — INDÉPENDANT du droit (valeurs par défaut tant que tu les as pas réglées)
var live_l_yaw: float = ARM_L_PIVOT_YAW
var live_l_sh_x_rot: float = 0.0
var live_l_sh_z_rot: float = 0.0
var live_l_f_yaw: float = 0.0
var live_l_x_rot: float = FOREARM_L_X_ROT
var live_l_z_rot: float = FOREARM_L_Z_ROT
var live_l_h_yaw: float = 0.0
var live_l_hand_x_rot: float = 0.0
var live_l_hand_z_rot: float = 0.0
# Globaux (pas de version L) — Valeurs initiales = pose finalisée
var live_arm_z: float = 0.10
var live_rig_x: float = 0.0
var live_rig_y: float = 0.0
var live_rig_z: float = 0.25
var live_rig_pitch: float = 0.0
# === ZOOM (ADS - Aim Down Sights) — uniquement pour l'arbalète ===
# Valeurs cibles pour la pose ZOOM (arme rapprochée du visage, comme une lunette).
# Quand zoom_active=true, on lerp les live_* vers ces cibles + on baisse la FOV.
var zoom_active: bool = false
var zoom_t: float = 0.0          # Progression de la transition 0..1 (0=normal, 1=zoom complet)
const ZOOM_SPEED := 8.0          # Vitesse de transition (1/durée). 8 = ~0.13s pour atteindre 1
const FOV_NORMAL := 75.0
const FOV_ZOOM := 45.0           # Plus serré = grossissement de la cible
# Cibles bras DROIT en zoom (pose épaulée, arme alignée avec l'œil)
const ZOOM_R_YAW := 0.0
const ZOOM_R_SH_X := -0.20       # Lever un peu l'épaule
const ZOOM_R_SH_Z := 0.10
const ZOOM_R_F_YAW := 0.20
const ZOOM_R_F_X := 1.20         # Coude plié pour ramener l'arbalète vers le visage
const ZOOM_R_F_Z := 0.0
const ZOOM_R_H_YAW := 0.0
const ZOOM_R_H_X := -1.20
const ZOOM_R_H_Z := 0.0
# Cibles bras GAUCHE en zoom (tendu vers l'avant pour soutenir le fût)
const ZOOM_L_YAW := 0.30
const ZOOM_L_SH_X := -0.15
const ZOOM_L_SH_Z := -0.30
const ZOOM_L_F_YAW := 0.0
const ZOOM_L_F_X := -0.40
const ZOOM_L_F_Z := 0.0
const ZOOM_L_H_YAW := 0.0
const ZOOM_L_H_X := 0.0
const ZOOM_L_H_Z := 0.0
# Globaux en zoom
const ZOOM_RIG_X := -0.10        # Décalage léger pour centrer l'arbalète sur l'écran
const ZOOM_RIG_Y := 0.05
const ZOOM_RIG_Z := -0.10        # Avancer un peu vers la cible
const ZOOM_R_PIT := -0.10
const ZOOM_ARM_Z := -0.20
var world_shoulder: Node3D       # ref vers le pivot épaule du bras du monde
var world_forearm: MeshInstance3D # ref vers le cube avant-bras
var world_hand: MeshInstance3D    # ref vers le cube main
var world_holder_ref: Node3D     # ref vers le holder (bouton TOGGLE le cache/montre)
var world_panel_canvas: CanvasLayer  # ref vers le canvas du panneau
var hide_button: Button          # ref vers le bouton TOGGLE (pour changer son texte)
var photo_button: Button         # ref vers le bouton POSSESS MANNEQUIN
var side_button: Button          # ref vers le bouton SIDE (R / L)
var photo_mode := false          # true = possession mannequin (vue 1ère personne)
var saved_player_pos: Vector3    # position joueur sauvegardée pour le retour
var saved_player_rot: float      # rotation Y du joueur sauvegardée
var mannequin_head_pos: Vector3  # position globale de la tête du mannequin
var world_visible := true        # état du mannequin (visible/caché)
var hud_yaw_label: Label
var hud_spread_label: Label
var hud_sh_x_label: Label
var hud_sh_z_label: Label
var hud_f_yaw_label: Label
var hud_x_label: Label
var hud_z_label: Label
var hud_h_yaw_label: Label
var hud_hand_x_label: Label
var hud_hand_z_label: Label
var hud_arm_z_label: Label
var hud_rig_x_label: Label
var hud_rig_y_label: Label
var hud_rig_z_label: Label
var hud_rig_pitch_label: Label
const ANGLE_STEP := 0.05         # pas d'incrément des boutons +/-
# Variables qui ont une version pour chaque bras (side-aware via editing_side)
const SIDE_AWARE_VARS := ["yaw", "sh_x_rot", "sh_z_rot", "f_yaw", "x_rot", "z_rot", "h_yaw", "hand_x_rot", "hand_z_rot"]

# Helper : modifie la bonne variable (R ou L) selon editing_side, puis update.
func _adjust(base: String, sign: int) -> void:
	var step = ANGLE_STEP * sign
	var var_name: String
	if base in SIDE_AWARE_VARS:
		var_name = ("live_l_" if editing_side == "L" else "live_") + base
	else:
		var_name = "live_" + base
	set(var_name, get(var_name) + step)
	update_world_arm()

# Callbacks +/- — utilisent _adjust() qui choisit R ou L automatiquement.
func _on_yaw_minus() -> void:    _adjust("yaw", -1)
func _on_yaw_plus() -> void:     _adjust("yaw", 1)
func _on_spread_minus() -> void: _adjust("spread", -1)
func _on_spread_plus() -> void:  _adjust("spread", 1)
func _on_sh_x_minus() -> void:   _adjust("sh_x_rot", -1)
func _on_sh_x_plus() -> void:    _adjust("sh_x_rot", 1)
func _on_sh_z_minus() -> void:   _adjust("sh_z_rot", -1)
func _on_sh_z_plus() -> void:    _adjust("sh_z_rot", 1)
func _on_f_yaw_minus() -> void:  _adjust("f_yaw", -1)
func _on_f_yaw_plus() -> void:   _adjust("f_yaw", 1)
func _on_x_minus() -> void:      _adjust("x_rot", -1)
func _on_x_plus() -> void:       _adjust("x_rot", 1)
func _on_z_minus() -> void:      _adjust("z_rot", -1)
func _on_z_plus() -> void:       _adjust("z_rot", 1)
func _on_h_yaw_minus() -> void:  _adjust("h_yaw", -1)
func _on_h_yaw_plus() -> void:   _adjust("h_yaw", 1)
func _on_hand_x_minus() -> void: _adjust("hand_x_rot", -1)
func _on_hand_x_plus() -> void:  _adjust("hand_x_rot", 1)
func _on_hand_z_minus() -> void: _adjust("hand_z_rot", -1)
func _on_hand_z_plus() -> void:  _adjust("hand_z_rot", 1)
func _on_arm_z_minus() -> void:  _adjust("arm_z", -1)
func _on_arm_z_plus() -> void:   _adjust("arm_z", 1)
func _on_rig_x_minus() -> void:  _adjust("rig_x", -1)
func _on_rig_x_plus() -> void:   _adjust("rig_x", 1)
func _on_rig_y_minus() -> void:  _adjust("rig_y", -1)
func _on_rig_y_plus() -> void:   _adjust("rig_y", 1)
func _on_rig_z_minus() -> void:  _adjust("rig_z", -1)
func _on_rig_z_plus() -> void:   _adjust("rig_z", 1)
func _on_rig_pitch_minus() -> void: _adjust("rig_pitch", -1)
func _on_rig_pitch_plus() -> void:  _adjust("rig_pitch", 1)

# TOGGLE SIDE : switch entre éditer le bras DROIT (R) ou GAUCHE (L)
func _on_side_toggle() -> void:
	editing_side = "L" if editing_side == "R" else "R"
	if side_button:
		side_button.text = "EDIT: %s (tap to switch)" % editing_side
	update_world_arm()  # refresh labels avec valeurs du bras sélectionné

@onready var camera: Camera3D = $Camera3D
@onready var arm_pivot: Node3D = $Camera3D/ArmPivot
# Caméra 3ème personne (créée dynamiquement) — placée derrière le joueur, +1.5m haut
# Pas une vraie TPS de jeu, juste un outil pour voir son perso de l'extérieur (debug + emotes)
var tps_camera: Camera3D
var tps_active := false

func _ready():
	build_arms()
	build_player_body()
	# Init du sway : on synchronise prev_yaw/prev_pitch à la rotation actuelle
	# pour éviter un delta énorme à la première frame.
	prev_yaw = rotation.y
	prev_pitch = cam_pitch
	shoot_ray = RayCast3D.new()
	shoot_ray.target_position = Vector3(0, 0, -xbow_range)
	shoot_ray.enabled = true
	camera.add_child(shoot_ray)
	# === CAMÉRA 3ème PERSONNE ===
	# Créée comme enfant du player (pas de la caméra FPS pour ne pas bouger avec elle).
	# Position : 3.5m derrière le joueur, 2m de haut, regarde vers l'avant.
	# Désactivée par défaut. Toggle via toggle_tps_view() depuis le HUD.
	tps_camera = Camera3D.new()
	tps_camera.name = "TPSCamera"
	tps_camera.position = Vector3(0, 2.0, 3.5)  # Derrière le joueur
	tps_camera.rotation_degrees = Vector3(-15, 0, 0)  # Légèrement penchée vers le bas
	tps_camera.fov = 75.0
	tps_camera.current = false
	add_child(tps_camera)
	shoot_sfx = AudioStreamPlayer.new()
	shoot_sfx.stream = load("res://sounds/xbow_shoot.wav")
	shoot_sfx.volume_db = -12.0
	add_child(shoot_sfx)
	# === SYSTÈME D'ARMES (nouveau) ===
	# Instancie les 2 nodes enfants, attache les scripts, et équipe l'arbalète.
	# Ordre important : le Controller doit exister AVANT l'Inventory (qui le référence).
	weapon_controller = Node.new()
	weapon_controller.name = "WeaponController"
	weapon_controller.set_script(load("res://weapon_controller.gd"))
	add_child(weapon_controller)
	weapon_inventory = Node.new()
	weapon_inventory.name = "WeaponInventory"
	weapon_inventory.set_script(load("res://weapon_inventory.gd"))
	add_child(weapon_inventory)
	# Équipe l'arbalète par défaut si has_xbow (compat avec l'ancien système)
	if has_xbow:
		var xbow_data: Resource = load("res://weapons/crossbow.tres")
		# FALLBACK : si le .tres est introuvable/corrompu, on crée la data en code.
		# Comme ça l'attaque marche toujours, même en cas de pb de chargement.
		if xbow_data == null:
			push_warning("crossbow.tres introuvable, création en code (fallback)")
			xbow_data = WeaponData.new()
			xbow_data.id = "crossbow"
			xbow_data.weapon_name = "Arbalète"
			xbow_data.type = WeaponData.WeaponType.RANGED_CROSSBOW
			xbow_data.damage = 25
			xbow_data.cooldown = 1.2
			xbow_data.range_max = 40.0
			xbow_data.ammo_max = -1
			xbow_data.sound_shoot = load("res://sounds/xbow_shoot.wav")
			xbow_data.sound_volume_db = -12.0
		weapon_inventory.add_weapon(xbow_data)
	# === ÉPÉE : 2ème slot ===
	# Équipée d'office pour test. Plus tard, elle sera débloquée via la Forge.
	var sword_data: Resource = load("res://weapons/sword.tres")
	if sword_data == null:
		push_warning("sword.tres introuvable, création en code (fallback)")
		sword_data = WeaponData.new()
		sword_data.id = "sword"
		sword_data.weapon_name = "Épée"
		sword_data.type = WeaponData.WeaponType.MELEE_SWORD
		sword_data.damage = 15
		sword_data.cooldown = 0.4
		sword_data.range_max = 2.5
		sword_data.ammo_max = -1
	weapon_inventory.add_weapon(sword_data)
	# Spawn cubes flottants dans le monde si INSPECT_WORLD activé.
	# call_deferred pour que ça s'exécute après que le player soit dans la scène
	# (sinon get_parent() pourrait être null ou global_position pas fiable).
	if INSPECT_WORLD:
		call_deferred("spawn_world_inspect_cubes")

# Pose un BRAS ARTICULÉ HIÉRARCHISÉ dans le monde (pas dans la caméra) à la même
# échelle que les bras du rig FPS. Le joueur peut tourner autour avec son perso
# pour screenshoter sous tous les angles, ET ajuster les angles EN LIVE via un
# panneau de boutons +/- qui s'affiche en haut à gauche de l'écran.
func spawn_world_inspect_cubes() -> void:
	var skin = _mat(Color(0.6, 0.48, 0.35), 0.85)
	var glove = _mat(Color(0.18, 0.13, 0.08), 0.9)
	var armor = _mat(Color(0.22, 0.22, 0.25), 0.4, 0.7)
	var armor_red = _mat(Color(0.55, 0.15, 0.15), 0.6)
	var pants = _mat(Color(0.25, 0.20, 0.15), 0.9)
	var holder = Node3D.new()
	holder.name = "WorldInspectMannequin"
	get_parent().add_child(holder)
	# Mannequin posé au sol (Y=0 absolu) à 4m devant le spawn.
	# On force Y=0 car au _ready() le player n'a pas encore subi la gravité,
	# sa global_position.y peut être en l'air → le mannequin flotterait.
	holder.global_position = Vector3(global_position.x, 0, global_position.z - 4.0)
	# Sauvegarde la position globale de la tête (pour POSSESS MANNEQUIN)
	# Tête mannequin : Y=1.71 dans le holder + Y=0.05 pour être à hauteur des yeux
	mannequin_head_pos = holder.global_position + Vector3(0, 1.76, 0)
	# ── PIEDS (Y=0.05, avancés en Z négatif pour matcher la face/yeux) ──
	_cube(holder, Vector3(-0.12, 0.05, -0.05), Vector3(0.16, 0.10, 0.30), pants)
	_cube(holder, Vector3(0.12, 0.05, -0.05), Vector3(0.16, 0.10, 0.30), pants)
	# ── JAMBES : cuisses (Y=0.33, allongées) + tibias (Y=0.71) ──
	_cube(holder, Vector3(-0.12, 0.33, 0), Vector3(0.20, 0.46, 0.20), pants)
	_cube(holder, Vector3(0.12, 0.33, 0), Vector3(0.20, 0.46, 0.20), pants)
	_cube(holder, Vector3(-0.12, 0.71, 0), Vector3(0.18, 0.30, 0.18), pants)
	_cube(holder, Vector3(0.12, 0.71, 0), Vector3(0.18, 0.30, 0.18), pants)
	# ── BASSIN (Y=1.01) ──
	_cube(holder, Vector3(0, 1.01, 0), Vector3(0.34, 0.20, 0.22), pants)
	# ── TORSE (Y=1.31, armor noir avec accent rouge) ──
	_cube(holder, Vector3(0, 1.31, 0), Vector3(0.40, 0.40, 0.25), armor)
	_cube(holder, Vector3(0, 1.31, -0.13), Vector3(0.10, 0.20, 0.02), armor_red)
	# ── TÊTE (Y=1.71, top à 1.85m = taille 1m85) ──
	_cube(holder, Vector3(0, 1.71, 0), Vector3(0.28, 0.28, 0.28), skin)
	_cube(holder, Vector3(0.075, 1.73, -0.145), Vector3(0.045, 0.035, 0.01), armor_red)
	_cube(holder, Vector3(-0.075, 1.73, -0.145), Vector3(0.045, 0.035, 0.01), armor_red)
	# ── ÉPAULES (armor, Y=1.51) ──
	_cube(holder, Vector3(0.30, 1.51, 0), Vector3(0.17, 0.10, 0.17), armor)
	_cube(holder, Vector3(-0.30, 1.51, 0), Vector3(0.17, 0.10, 0.17), armor)
	# ── BRAS DROIT ARTICULÉ (modifiable via panneau live) ──
	# Note : sur le mannequin (vue extérieure), le biceps PEND VERTICAL (long en Y).
	# Donc on swap Y et Z de BICEPS_SIZE = (0.16, 0.14, 0.28) → (0.16, 0.28, 0.14).
	# Pareil pour FOREARM_SIZE qui était déjà long en Y, on le garde tel quel.
	var biceps_size_v = Vector3(BICEPS_SIZE.x, BICEPS_SIZE.z, BICEPS_SIZE.y)
	var shoulder = Node3D.new()
	shoulder.name = "ShoulderPivot"
	shoulder.position = Vector3(0.30, 1.46, 0)
	shoulder.rotation = Vector3(live_sh_x_rot, live_yaw, live_sh_z_rot)
	holder.add_child(shoulder)
	world_shoulder = shoulder
	# Biceps droit VERTICAL (top au niveau de l'épaule, descend de 0.28m)
	_cube(shoulder, Vector3(0, -0.14, 0), biceps_size_v, skin)
	# Pivot coude (au bas du biceps)
	var elbow = Node3D.new()
	elbow.name = "ElbowPivot"
	elbow.position = Vector3(0, -0.28, 0)
	shoulder.add_child(elbow)
	# Avant-bras avec rotations live (descend du coude)
	# Centre Y=-0.12 dans elbow, hauteur 0.24 → bottom local du forearm à Y=-0.12
	var forearm = _cube(elbow, Vector3(0, -0.12, 0), FOREARM_SIZE, skin)
	forearm.rotation.x = live_x_rot
	forearm.rotation.z = live_z_rot
	world_forearm = forearm
	# Main droite ENFANT de l'avant-bras (suit ses rotations + ses propres rotations)
	# Position locale dans forearm : Y=-0.17 = bottom forearm (-0.12) - demi-hauteur main (0.05)
	var hand = _cube(forearm, Vector3(0, -0.17, 0), HAND_SIZE, glove)
	hand.rotation.x = live_hand_x_rot
	hand.rotation.z = live_hand_z_rot
	world_hand = hand
	# ── BRAS GAUCHE STATIQUE (mirror du droit, vertical, pose neutre) ──
	# Biceps gauche vertical : centre Y=1.32 → top à 1.46 (épaule), bottom à 1.18
	_cube(holder, Vector3(-0.30, 1.32, 0), biceps_size_v, skin)
	# Avant-bras gauche : centre Y=1.06 → top à 1.18, bottom à 0.94
	_cube(holder, Vector3(-0.30, 1.06, 0), FOREARM_SIZE, skin)
	# Main gauche : centre Y=0.89 → top à 0.94, bottom à 0.84
	_cube(holder, Vector3(-0.30, 0.89, 0), HAND_SIZE, glove)
	# Créer le panneau de contrôle in-game
	create_inspect_panel(holder)

# Crée un panneau HUD en haut à gauche avec 3 lignes (YAW, X, Z), chaque ligne
# avec valeur affichée + bouton "−" + bouton "+", plus un bouton HIDE pour cacher
# le bras du monde quand tu veux jouer normalement.
func create_inspect_panel(holder: Node3D) -> void:
	world_holder_ref = holder  # ref pour le bouton HIDE
	var canvas = CanvasLayer.new()
	canvas.name = "InspectPanel"
	canvas.layer = 100  # au-dessus du HUD normal
	add_child(canvas)
	world_panel_canvas = canvas  # ref pour le bouton HIDE
	# === ARCHITECTURE : Panel + Bouton SIDE FIXE en haut + ScrollContainer dessous ===
	# Le bouton SIDE est sorti du scroll pour rester toujours visible.
	# Le ScrollContainer dessous contient les 18 contrôles + boutons d'action.
	var panel = Panel.new()
	panel.position = Vector2(20, 50)
	panel.size = Vector2(440, 1000)
	panel.modulate.a = 0.92
	canvas.add_child(panel)
	# Bouton SIDE FIXE en haut du panel (hors scroll, toujours visible)
	side_button = Button.new()
	side_button.position = Vector2(8, 8)
	side_button.size = Vector2(424, 90)
	side_button.text = "EDIT: %s  (tap to switch)" % editing_side
	side_button.add_theme_font_size_override("font_size", 32)
	side_button.pressed.connect(_on_side_toggle)
	panel.add_child(side_button)
	# ScrollContainer EN-DESSOUS du bouton SIDE
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(8, 106)  # 8 (top) + 90 (bouton) + 8 (gap)
	scroll.size = Vector2(424, 886)    # 1000 - 106 - 8 = 886
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	# VBoxContainer dans le scroll, étendu en largeur
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	# === PRESETS : 3 boutons en haut pour appliquer des poses pré-réglées ===
	# Tu tape un preset → toutes les valeurs sont appliquées d'un coup. Peaufine avec +/-.
	var preset_xbow = Button.new()
	preset_xbow.text = "PRESET: ARBALÈTE EN VISÉE"
	preset_xbow.add_theme_font_size_override("font_size", 24)
	preset_xbow.custom_minimum_size = Vector2(0, 80)
	preset_xbow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_xbow.pressed.connect(_on_preset_xbow)
	vbox.add_child(preset_xbow)
	var preset_sword = Button.new()
	preset_sword.text = "PRESET: ÉPÉE PRÊTE"
	preset_sword.add_theme_font_size_override("font_size", 24)
	preset_sword.custom_minimum_size = Vector2(0, 80)
	preset_sword.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_sword.pressed.connect(_on_preset_sword)
	vbox.add_child(preset_sword)
	var preset_idle = Button.new()
	preset_idle.text = "PRESET: DÉTENDU"
	preset_idle.add_theme_font_size_override("font_size", 24)
	preset_idle.custom_minimum_size = Vector2(0, 80)
	preset_idle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_idle.pressed.connect(_on_preset_idle)
	vbox.add_child(preset_idle)
	# Tous les contrôles à plat — tu scrolles pour voir tout
	hud_yaw_label    = _make_inspect_row(vbox, "S_YAW", live_yaw,         "_on_yaw_minus",    "_on_yaw_plus")
	hud_spread_label = _make_inspect_row(vbox, "SPRD ", live_spread,      "_on_spread_minus", "_on_spread_plus")
	hud_sh_x_label   = _make_inspect_row(vbox, "S_X  ", live_sh_x_rot,    "_on_sh_x_minus",   "_on_sh_x_plus")
	hud_sh_z_label   = _make_inspect_row(vbox, "S_Z  ", live_sh_z_rot,    "_on_sh_z_minus",   "_on_sh_z_plus")
	hud_f_yaw_label  = _make_inspect_row(vbox, "F_YAW", live_f_yaw,       "_on_f_yaw_minus",  "_on_f_yaw_plus")
	hud_x_label      = _make_inspect_row(vbox, "F_X  ", live_x_rot,       "_on_x_minus",      "_on_x_plus")
	hud_z_label      = _make_inspect_row(vbox, "F_Z  ", live_z_rot,       "_on_z_minus",      "_on_z_plus")
	hud_h_yaw_label  = _make_inspect_row(vbox, "H_YAW", live_h_yaw,       "_on_h_yaw_minus",  "_on_h_yaw_plus")
	hud_hand_x_label = _make_inspect_row(vbox, "H_X  ", live_hand_x_rot,  "_on_hand_x_minus", "_on_hand_x_plus")
	hud_hand_z_label = _make_inspect_row(vbox, "H_Z  ", live_hand_z_rot,  "_on_hand_z_minus", "_on_hand_z_plus")
	hud_arm_z_label  = _make_inspect_row(vbox, "ARM_Z", live_arm_z,       "_on_arm_z_minus",  "_on_arm_z_plus")
	hud_rig_x_label  = _make_inspect_row(vbox, "RIG_X", live_rig_x,       "_on_rig_x_minus",  "_on_rig_x_plus")
	hud_rig_y_label  = _make_inspect_row(vbox, "RIG_Y", live_rig_y,       "_on_rig_y_minus",  "_on_rig_y_plus")
	hud_rig_z_label  = _make_inspect_row(vbox, "RIG_Z", live_rig_z,       "_on_rig_z_minus",  "_on_rig_z_plus")
	hud_rig_pitch_label = _make_inspect_row(vbox, "R_PIT", live_rig_pitch, "_on_rig_pitch_minus", "_on_rig_pitch_plus")
	# Bouton POSSESS MANNEQUIN
	photo_button = Button.new()
	photo_button.text = "POSSESS"
	photo_button.add_theme_font_size_override("font_size", 28)
	photo_button.custom_minimum_size = Vector2(0, 90)
	photo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	photo_button.pressed.connect(_on_photo_toggle)
	vbox.add_child(photo_button)
	# Bouton TOGGLE HIDE
	hide_button = Button.new()
	hide_button.text = "HIDE"
	hide_button.add_theme_font_size_override("font_size", 28)
	hide_button.custom_minimum_size = Vector2(0, 90)
	hide_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hide_button.pressed.connect(_on_hide_inspect)
	vbox.add_child(hide_button)

# === PRESETS : poses pré-réglées appliquées d'un seul tap ===
# Modifie toutes les variables live_* d'un coup. Tu peaufines avec +/- après.
func _apply_preset(preset_name: String) -> void:
	# Reset position globale du rig
	live_rig_x = 0.0; live_rig_y = 0.0; live_rig_z = 0.0; live_rig_pitch = 0.0
	live_arm_z = 0.0
	live_spread = ARM_PIVOT_X
	match preset_name:
		"crossbow_aim":
			# Pose "viseur arbalète" : arme proche du visage, bras pliés, comme un fusil épaulé
			# Bras DROIT : tient la crosse contre l'épaule, coude plié vers le haut
			live_yaw = 0.10;       live_sh_x_rot = -0.30;  live_sh_z_rot = 0.20
			live_f_yaw = 0.0;      live_x_rot = -0.80;     live_z_rot = 0.0
			live_h_yaw = 0.0;      live_hand_x_rot = 0.0;  live_hand_z_rot = 0.0
			# Bras GAUCHE : tendu vers l'avant pour soutenir le fût de l'arbalète
			live_l_yaw = 0.30;     live_l_sh_x_rot = -0.20; live_l_sh_z_rot = -0.30
			live_l_f_yaw = 0.0;    live_l_x_rot = -0.40;    live_l_z_rot = 0.0
			live_l_h_yaw = 0.0;    live_l_hand_x_rot = 0.0; live_l_hand_z_rot = 0.0
			live_arm_z = -0.10
		"sword_ready":
			# Pose "épée prête" : épée tenue verticalement à droite, bras gauche détendu
			# Bras DROIT : tient l'épée verticalement, légèrement écartée
			live_yaw = 0.15;       live_sh_x_rot = -0.10;  live_sh_z_rot = 0.10
			live_f_yaw = 0.0;      live_x_rot = -0.40;     live_z_rot = -0.20
			live_h_yaw = 0.0;      live_hand_x_rot = 0.0;  live_hand_z_rot = 0.0
			# Bras GAUCHE : pendu naturellement le long du corps
			live_l_yaw = 0.0;      live_l_sh_x_rot = 0.0;  live_l_sh_z_rot = 0.0
			live_l_f_yaw = 0.0;    live_l_x_rot = -0.10;   live_l_z_rot = 0.0
			live_l_h_yaw = 0.0;    live_l_hand_x_rot = 0.0; live_l_hand_z_rot = 0.0
		"idle_relaxed":
			# Pose "détendue" : bras pendus naturellement, arme tenue de manière relax
			live_yaw = 0.05;       live_sh_x_rot = 0.0;    live_sh_z_rot = 0.0
			live_f_yaw = 0.0;      live_x_rot = -0.20;     live_z_rot = -0.20
			live_h_yaw = 0.0;      live_hand_x_rot = 0.0;  live_hand_z_rot = 0.0
			live_l_yaw = -0.05;    live_l_sh_x_rot = 0.0;  live_l_sh_z_rot = 0.0
			live_l_f_yaw = 0.0;    live_l_x_rot = -0.20;   live_l_z_rot = 0.0
			live_l_h_yaw = 0.0;    live_l_hand_x_rot = 0.0; live_l_hand_z_rot = 0.0
	update_world_arm()
	print("[PRESET] Applied: ", preset_name)

func _on_preset_xbow() -> void:  _apply_preset("crossbow_aim")
func _on_preset_sword() -> void: _apply_preset("sword_ready")
func _on_preset_idle() -> void:  _apply_preset("idle_relaxed")

# TOGGLE POSSESS MANNEQUIN : téléporte le joueur à la place du mannequin (vue
# 1ère personne, hauteur des yeux) pour voir le rig FPS depuis cette position.
# Cache le mannequin (sinon on serait dedans), désactive gravité + invincible.
# Re-tap : restaure position d'origine + ré-affiche le mannequin.
func _on_photo_toggle() -> void:
	photo_mode = !photo_mode
	if photo_mode:
		# ENTRÉE : sauvegarde + téléporte à la tête du mannequin
		saved_player_pos = global_position
		saved_player_rot = rotation.y
		# Calcule l'offset entre la caméra (yeux) et le centre du player.
		# On veut que camera.global_position == mannequin_head_pos après téléportation.
		# Donc player.global_position = mannequin_head_pos - camera_offset
		var cam_offset = camera.global_position - global_position
		global_position = mannequin_head_pos - cam_offset
		rotation.y = 0  # mannequin regarde vers -Z (forward Godot)
		# Cache les bras FPS du joueur (sinon ils parasitent la vue du mannequin)
		if fps_arms: fps_arms.visible = false
		# Cache le mannequin pour pas voir les cubes du corps autour de la caméra
		if world_holder_ref:
			world_holder_ref.visible = false
			world_visible = false
		if hide_button: hide_button.text = "SHOW (afficher le bras)"
		if photo_button: photo_button.text = "EXIT POSSESS"
	else:
		# SORTIE : restaure position + ré-affiche le mannequin + bras FPS
		global_position = saved_player_pos
		rotation.y = saved_player_rot
		if fps_arms: fps_arms.visible = true
		if world_holder_ref:
			world_holder_ref.visible = true
			world_visible = true
		if hide_button: hide_button.text = "HIDE (cacher le bras)"
		if photo_button: photo_button.text = "POSSESS MANNEQUIN"

# TOGGLE : cache ou ré-affiche le mannequin (panneau reste visible pour pouvoir
# le ré-afficher après avoir tué les ennemis)
func _on_hide_inspect() -> void:
	world_visible = !world_visible
	if world_holder_ref:
		world_holder_ref.visible = world_visible
	if hide_button:
		hide_button.text = "HIDE (cacher le bras)" if world_visible else "SHOW (afficher le bras)"

# Crée une ligne du panneau (label + 2 boutons), retourne le Label pour update live.
func _make_inspect_row(parent: Container, lbl: String, val: float, minus_cb: String, plus_cb: String) -> Label:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	# Label de la valeur (à gauche, prend la place restante)
	var label = Label.new()
	label.text = "%s: %+.2f" % [lbl, val]
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1, 1, 0.85))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)
	# Bouton MOINS (gros et confortable pour gros doigts)
	var btn_minus = Button.new()
	btn_minus.text = "−"
	btn_minus.add_theme_font_size_override("font_size", 36)
	btn_minus.custom_minimum_size = Vector2(90, 90)
	btn_minus.pressed.connect(Callable(self, minus_cb))
	hbox.add_child(btn_minus)
	# Bouton PLUS
	var btn_plus = Button.new()
	btn_plus.text = "+"
	btn_plus.add_theme_font_size_override("font_size", 36)
	btn_plus.custom_minimum_size = Vector2(90, 90)
	btn_plus.pressed.connect(Callable(self, plus_cb))
	hbox.add_child(btn_plus)
	parent.add_child(hbox)
	return label

# Renvoie la valeur live actuelle pour un nom de variable de base.
# Utilise editing_side pour les variables side-aware.
func _get_live_value(base: String) -> float:
	var var_name: String
	if base in SIDE_AWARE_VARS:
		var_name = ("live_l_" if editing_side == "L" else "live_") + base
	else:
		var_name = "live_" + base
	return get(var_name)

# Applique les valeurs live_* au bras du monde + update les labels HUD.
# Imprime aussi dans la console Godot pour que tu puisses copier les valeurs
# vers les const finales une fois la pose validée.
func update_world_arm() -> void:
	if world_shoulder:
		world_shoulder.rotation = Vector3(live_sh_x_rot, live_yaw, live_sh_z_rot)
	if world_forearm:
		world_forearm.rotation = Vector3(live_x_rot, live_f_yaw, live_z_rot)
	if world_hand:
		world_hand.rotation = Vector3(live_hand_x_rot, live_h_yaw, live_hand_z_rot)
	# Labels affichent les valeurs du SIDE actuellement sélectionné (R ou L)
	var is_l = (editing_side == "L")
	var v_yaw      = live_l_yaw      if is_l else live_yaw
	var v_sh_x     = live_l_sh_x_rot if is_l else live_sh_x_rot
	var v_sh_z     = live_l_sh_z_rot if is_l else live_sh_z_rot
	var v_f_yaw    = live_l_f_yaw    if is_l else live_f_yaw
	var v_x        = live_l_x_rot    if is_l else live_x_rot
	var v_z        = live_l_z_rot    if is_l else live_z_rot
	var v_h_yaw    = live_l_h_yaw    if is_l else live_h_yaw
	var v_hand_x   = live_l_hand_x_rot if is_l else live_hand_x_rot
	var v_hand_z   = live_l_hand_z_rot if is_l else live_hand_z_rot
	if hud_yaw_label:    hud_yaw_label.text    = "S_YAW: %+.2f" % v_yaw
	if hud_spread_label: hud_spread_label.text = "SPRD : %+.2f" % live_spread
	if hud_sh_x_label:   hud_sh_x_label.text   = "S_X  : %+.2f" % v_sh_x
	if hud_sh_z_label:   hud_sh_z_label.text   = "S_Z  : %+.2f" % v_sh_z
	if hud_f_yaw_label:  hud_f_yaw_label.text  = "F_YAW: %+.2f" % v_f_yaw
	if hud_x_label:      hud_x_label.text      = "F_X  : %+.2f" % v_x
	if hud_z_label:      hud_z_label.text      = "F_Z  : %+.2f" % v_z
	if hud_h_yaw_label:  hud_h_yaw_label.text  = "H_YAW: %+.2f" % v_h_yaw
	if hud_hand_x_label: hud_hand_x_label.text = "H_X  : %+.2f" % v_hand_x
	if hud_hand_z_label: hud_hand_z_label.text = "H_Z  : %+.2f" % v_hand_z
	if hud_arm_z_label:  hud_arm_z_label.text  = "ARM_Z: %+.2f" % live_arm_z
	if hud_rig_x_label:  hud_rig_x_label.text  = "RIG_X: %+.2f" % live_rig_x
	if hud_rig_y_label:  hud_rig_y_label.text  = "RIG_Y: %+.2f" % live_rig_y
	if hud_rig_z_label:  hud_rig_z_label.text  = "RIG_Z: %+.2f" % live_rig_z
	if hud_rig_pitch_label: hud_rig_pitch_label.text = "R_PIT: %+.2f" % live_rig_pitch
	print("[%s] sh=%.2f|%.2f|%.2f f=%.2f|%.2f|%.2f h=%.2f|%.2f|%.2f" % [editing_side, v_yaw, v_sh_x, v_sh_z, v_f_yaw, v_x, v_z, v_h_yaw, v_hand_x, v_hand_z])

func _cube(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var c = MeshInstance3D.new()
	var m = BoxMesh.new()
	m.size = size
	m.material = mat
	c.mesh = m
	c.position = pos
	parent.add_child(c)
	return c

func _mat(c: Color, r:=0.85, m:=0.0) -> StandardMaterial3D:
	var mt = StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = r
	mt.metallic = m
	return mt

# Crée une main détaillée (6 cubes) : paume + pouce + 4 doigts.
# - parent : le node parent (ex: hand_pivot)
# - pos : position de la PAUME dans le parent
# - mirror : true = main gauche (pouce inversé en X)
# Retourne le Node3D conteneur (utile si on veut le toggle visible/invisible).
func _make_detailed_hand(parent: Node3D, pos: Vector3, mirror: bool = false) -> Node3D:
	var glove = _mat(Color(0.18, 0.13, 0.08), 0.9)
	# Conteneur pour pouvoir tout cacher/afficher d'un coup
	var hand_container = Node3D.new()
	hand_container.position = pos
	parent.add_child(hand_container)
	# Direction du pouce : positif (droite) pour main droite, négatif (gauche) pour gauche
	var thumb_dir = -1.0 if mirror else 1.0
	# ── PAUME (cube rectangulaire central) ──
	# X = largeur (côté à côté), Y = épaisseur (peu épaisse), Z = longueur de la main (avant)
	_cube(hand_container, Vector3(0, 0, 0), Vector3(0.10, 0.04, 0.10), glove)
	# ── 4 DOIGTS — alignés devant la paume (Z négatif = vers l'avant) ──
	# Chaque doigt fait 2 cm de large, 3 cm de long. Espacés de 2.5 cm.
	# Positions X : -0.0375, -0.0125, +0.0125, +0.0375 (4 doigts répartis sur 7.5 cm)
	var finger_size = Vector3(0.022, 0.035, 0.05)
	_cube(hand_container, Vector3(-0.0375, 0, -0.075), finger_size, glove)  # Auriculaire
	_cube(hand_container, Vector3(-0.0125, 0, -0.075), finger_size, glove)  # Annulaire
	_cube(hand_container, Vector3( 0.0125, 0, -0.075), finger_size, glove)  # Majeur
	_cube(hand_container, Vector3( 0.0375, 0, -0.075), finger_size, glove)  # Index
	# ── POUCE — sur le côté de la paume, plus court et plus épais ──
	_cube(hand_container, Vector3(0.06 * thumb_dir, 0, -0.025), Vector3(0.025, 0.035, 0.04), glove)
	return hand_container

func build_arms():
	fps_arms = Node3D.new()
	# ── MATÉRIAUX PARTAGÉS ──
	var skin = _mat(Color(0.6, 0.48, 0.35), 0.85)
	var glove = _mat(Color(0.18, 0.13, 0.08), 0.9)
	var armor = _mat(Color(0.22, 0.22, 0.25), 0.4, 0.7)
	# ── MODE INSPECT : 3 cubes flottants OU 1 bras articulé devant la caméra ──
	# Workflow :
	#   INSPECT_MODE=true + INSPECT_ANGLES=false → voir les TAILLES (3 cubes alignés)
	#   INSPECT_MODE=true + INSPECT_ANGLES=true  → voir les ANGLES (1 bras articulé)
	#   INSPECT_MODE=false                       → rig FPS complet normal
	if INSPECT_MODE:
		if INSPECT_ANGLES:
			# 1 bras articulé devant la caméra : épaule → biceps → avant-bras → main
			# Les angles ARM_PIVOT_YAW + FOREARM_X_ROT + FOREARM_Z_ROT sont appliqués
			# par _physics_process via les refs arm_r_pivot_ref et forearm_x_ref.
			# Modifier les constantes en haut → relancer Godot → voir l'effet immédiat.
			var insp_pivot = Node3D.new()
			insp_pivot.name = "InspectPivot"
			insp_pivot.position = Vector3(0, 0.15, -1.3)  # Devant la caméra, légèrement en haut
			insp_pivot.rotation.y = ARM_PIVOT_YAW
			fps_arms.add_child(insp_pivot)
			arm_r_pivot_ref = insp_pivot  # _physics_process applique ARM_PIVOT_YAW chaque frame
			# Biceps : centré sur le pivot (origine de l'épaule)
			_cube(insp_pivot, Vector3(0, 0, 0), BICEPS_SIZE, skin)
			# Avant-bras : descend de Y=-0.20 (sous le biceps), avec rotations X et Z
			var insp_forearm = _cube(insp_pivot, Vector3(0, -0.20, 0), FOREARM_SIZE, skin)
			insp_forearm.rotation.x = FOREARM_X_ROT
			insp_forearm.rotation.z = FOREARM_Z_ROT
			forearm_x_ref = insp_forearm  # _physics_process applique les rotations chaque frame
			# Main : descend de Y=-0.40 (sous l'avant-bras)
			_cube(insp_pivot, Vector3(0, -0.40, 0), HAND_SIZE, glove)
		else:
			# 3 cubes alignés côte à côte : voir les tailles isolées sans rotation
			_cube(fps_arms, Vector3(-0.5, 0, -1.2), BICEPS_SIZE, skin)   # Biceps (gauche écran)
			_cube(fps_arms, Vector3(0.0,  0, -1.2), FOREARM_SIZE, skin)  # Avant-bras (centre)
			_cube(fps_arms, Vector3(0.5,  0, -1.2), HAND_SIZE, glove)    # Main droite (droite écran)
		arm_pivot.add_child(fps_arms)
		return
	# ── REFONTE 26 avril : BRAS DROIT SORTI DES KITS D'ARMES ──
	# Avant : biceps + avant-bras DUPLIQUÉS dans xbow_model ET sword_model.
	# Conséquence : quand xbow_model.visible = false au switch, les bras disparaissent
	# AVEC l'arbalète. Si sword_model est bugué (lame long en Z = invisible), on voit
	# RIEN → symptôme rapporté "biceps, avant-bras et main plus là".
	# Maintenant : biceps + avant-bras enfants DIRECTS de arm_r_pivot (toujours visibles).
	# xbow_model et sword_model contiennent UNIQUEMENT la main + l'arme spécifique.
	#
	# Référence : enemy.gd lignes 156-172 utilise body_root → arm_r_pivot → cubes
	# avec positions Y relatives en cascade (-0.3, -0.58, -0.82 = épaule, coude, main).
	#
	# ── GROUPE 1 : TORSE FPS ──
	# Les 2 épaules visibles. ARM_L_PIVOT_X = -0.30 (au lieu de -0.55) garde l'épaule
	# gauche dans le champ visuel mobile.
	var torso_arms = Node3D.new()
	torso_arms.name = "TorsoArms"
	fps_arms.add_child(torso_arms)
	# Épaule droite (armure)
	shoulder_r_cube_ref = _cube(torso_arms, Vector3(0.35, -0.22, -0.18), Vector3(0.17, 0.22, 0.17), armor)
	# Épaule gauche (armure, mirror du droit) — visible avec ARM_L_PIVOT_X corrigé
	shoulder_l_cube_ref = _cube(torso_arms, Vector3(-0.35, -0.22, -0.18), Vector3(0.17, 0.22, 0.17), armor)
	# ── PIVOT ÉPAULE DROITE ──
	# Position : à la base de l'épaule, point d'articulation naturel du bras.
	# Tout ce qui pend du bras (biceps, avant-bras, main, arme) est enfant de ce pivot.
	var arm_r_pivot = Node3D.new()
	arm_r_pivot.name = "ArmRPivot"
	arm_r_pivot.position = Vector3(ARM_PIVOT_X, ARM_PIVOT_Y, ARM_PIVOT_Z)
	arm_r_pivot.rotation.y = ARM_PIVOT_YAW
	arm_r_pivot_ref = arm_r_pivot
	fps_arms.add_child(arm_r_pivot)
	# ── BRAS DROIT ANATOMIQUE (DIRECT dans arm_r_pivot, jamais caché au switch) ──
	# Biceps : cube horizontal vers l'avant (forme la base du bras) — RACCOURCI
	_cube(arm_r_pivot, Vector3(0.10, -0.04, -0.20), BICEPS_SIZE, skin)
	# ── PIVOT COUDE (Node3D) — au TOP de l'avant-bras pour rotation propre ──
	# Ancien : rotations appliquées au cube forearm = pivot au centre du cube = bouge à peine.
	# Nouveau : pivot au coude (top du forearm) → vrai mouvement de coude visible.
	# Position : top du forearm = (0.10, -0.04, -0.42) dans arm_r_pivot.
	var elbow_pivot = Node3D.new()
	elbow_pivot.name = "ElbowPivot"
	elbow_pivot.position = Vector3(0.10, -0.04, -0.42)
	arm_r_pivot.add_child(elbow_pivot)
	forearm_x_ref = elbow_pivot   # F_X/F_YAW/F_Z appliquées au pivot coude
	forearm_s_ref = elbow_pivot   # ref dupliquée pour compat _physics_process
	# Avant-bras cube : enfant du pivot coude, centré sous l'origine pour que TOP=origine.
	_cube(elbow_pivot, Vector3(0, -0.12, 0), FOREARM_SIZE, skin)
	# ── PIVOT MAIN (HAND) — au BOTTOM de l'avant-bras (= au poignet) ──
	# Avant : hand_pivot était à l'origine arm_r_pivot (= épaule), donc H_X/H_Y/H_Z
	# faisaient pivoter la main autour de l'épaule = mouvement bizarre.
	# Maintenant : hand_pivot au bottom du forearm. H_X/H_Y/H_Z = vraie rotation poignet.
	# elbow_pivot est au top du forearm. Bottom = (0, -FOREARM_SIZE.y, 0) = (0, -0.24, 0)
	# en elbow_pivot.
	var hand_pivot = Node3D.new()
	hand_pivot.name = "HandPivot"
	hand_pivot.position = Vector3(0, -FOREARM_SIZE.y, 0)
	elbow_pivot.add_child(hand_pivot)
	hand_pivot_ref = hand_pivot
	# ── PIVOT ÉPAULE GAUCHE (indépendant du droit) ──
	# Le bras gauche a son propre pivot pour pas être affecté par la rotation du droit.
	var arm_l_pivot = Node3D.new()
	arm_l_pivot.name = "ArmLPivot"
	arm_l_pivot.position = Vector3(ARM_L_PIVOT_X, ARM_L_PIVOT_Y, ARM_L_PIVOT_Z)
	arm_l_pivot.rotation.y = ARM_L_PIVOT_YAW
	arm_l_pivot_ref = arm_l_pivot
	fps_arms.add_child(arm_l_pivot)
	# Bras gauche : biceps + avant-bras + main (mirror du droit) — RACCOURCIS
	_cube(arm_l_pivot, Vector3(-0.10, -0.04, -0.20), BICEPS_SIZE, skin)
	# ── PIVOT COUDE GAUCHE (mirror du droit) ──
	# Position : top du forearm gauche = (-0.10, -0.04, -0.42) dans arm_l_pivot
	var elbow_l_pivot = Node3D.new()
	elbow_l_pivot.name = "ElbowLPivot"
	elbow_l_pivot.position = Vector3(-0.10, -0.04, -0.42)
	arm_l_pivot.add_child(elbow_l_pivot)
	forearm_l_ref = elbow_l_pivot   # F_*  appliquées en MIRROR au pivot coude gauche
	# Avant-bras gauche : enfant du pivot coude, centré sous l'origine
	_cube(elbow_l_pivot, Vector3(0, -0.12, 0), FOREARM_SIZE, skin)
	# ── PIVOT MAIN GAUCHE — au bottom du forearm = au poignet ──
	var hand_l_pivot = Node3D.new()
	hand_l_pivot.name = "HandLPivot"
	hand_l_pivot.position = Vector3(0, -FOREARM_SIZE.y, 0)
	elbow_l_pivot.add_child(hand_l_pivot)
	hand_l_pivot_ref = hand_l_pivot
	# Main gauche gantée — enfant du hand_pivot, mirror de la main droite
	# Position dans hand_l_pivot pour que la main reste à (-0.05, -0.30, -0.52) dans arm_l_pivot
	# hand_l_pivot en arm_l_pivot = (-0.10, -0.28, -0.42), donc main locale = (0.05, -0.02, -0.10)
	# Main gauche INVISIBLE (cube présent pour la structure mais caché)
	# Main gauche INVISIBLE (le bout de l'avant-bras fait office de main, style Minecraft)
	# ── GROUPE 2 : KIT ARBALÈTE (enfant de arm_r_pivot, toggle au switch) ──
	# Contient SEULEMENT : main droite + main gauche posée + arbalète. Les bras restent
	# visibles via arm_r_pivot et arm_l_pivot, jamais cachés.
	xbow_model = Node3D.new()
	xbow_model.name = "XbowKit"
	hand_pivot.add_child(xbow_model)
	# Compense pour que les cubes main/arme (positionnés en référence à arm_r_pivot)
	# restent au même endroit visuel. hand_pivot est au bottom forearm =
	# (0.10, -0.28, -0.42) dans arm_r_pivot. Inverse pour ramener à (0, 0, 0).
	xbow_model.position = Vector3(-0.10, 0.28, 0.42)
	# Main droite INVISIBLE (tient la crosse de l'arbalète)
	# Pas de cubes de main : le bout de l'avant-bras (style Minecraft) tient l'arme.
	# Le hand_pivot (Node3D invisible) reste là pour les rotations H_X/H_Y/H_Z.
	# ── ARBALÈTE (cubes en relatif au pivot) ──
	var wood = _mat(Color(0.3, 0.2, 0.1), 0.9)
	var wood_dark = _mat(Color(0.22, 0.14, 0.07), 0.9)
	var metal_xb = _mat(Color(0.4, 0.4, 0.45), 0.3, 0.8)
	var string = _mat(Color(0.7, 0.65, 0.5), 0.6)
	# Crosse (stock)
	_cube(xbow_model, Vector3(0, -0.23, -0.37), Vector3(0.08, 0.1, 0.55), wood)
	_cube(xbow_model, Vector3(0, -0.16, -0.37), Vector3(0.1, 0.07, 0.5), wood_dark)
	# Pontet
	_cube(xbow_model, Vector3(0, -0.30, -0.22), Vector3(0.05, 0.08, 0.05), metal_xb)
	# Poignée
	_cube(xbow_model, Vector3(0, -0.33, -0.17), Vector3(0.08, 0.15, 0.1), wood_dark)
	# Arcs horizontaux
	_cube(xbow_model, Vector3(-0.19, -0.16, -0.60), Vector3(0.2, 0.06, 0.06), wood)
	_cube(xbow_model, Vector3(0.19, -0.16, -0.60), Vector3(0.2, 0.06, 0.06), wood)
	# Pointes de l'arc
	_cube(xbow_model, Vector3(-0.29, -0.16, -0.60), Vector3(0.04, 0.1, 0.06), wood_dark)
	_cube(xbow_model, Vector3(0.29, -0.16, -0.60), Vector3(0.04, 0.1, 0.06), wood_dark)
	# Corde
	_cube(xbow_model, Vector3(0, -0.16, -0.55), Vector3(0.58, 0.015, 0.015), string)
	# Carreau visible
	_cube(xbow_model, Vector3(0, -0.12, -0.47), Vector3(0.02, 0.02, 0.3), _mat(Color(0.35, 0.25, 0.15)))
	# Renforts métal
	_cube(xbow_model, Vector3(0, -0.16, -0.60), Vector3(0.14, 0.09, 0.04), metal_xb)
	# ── GROUPE 3 : KIT ÉPÉE (enfant de arm_r_pivot, toggle au switch) ──
	# Contient SEULEMENT : sword_pivot avec main droite + épée RECONSTRUITE long en Y.
	# RÈGLE D'OR du projet : NE JAMAIS faire un cube long en Z en FPS = invisible.
	# La lame DOIT monter en Y (vertical). Avant : size(0.07, 0.09, 0.4) = long en Z = bug.
	# Maintenant : size(0.08, 0.45, 0.04) = long en Y = visible au-dessus de la main.
	sword_model = Node3D.new()
	sword_model.name = "SwordKit"
	hand_pivot.add_child(sword_model)
	# Même compensation que xbow_model
	sword_model.position = Vector3(-0.10, 0.28, 0.42)
	# Sword_pivot : positionné à la main au bout de l'avant-bras (utilisé par les
	# anims de swing dans _physics_process, ne pas supprimer).
	sword_pivot = Node3D.new()
	sword_pivot.name = "SwordPivot"
	sword_pivot.position = Vector3(0.05, -0.30, -0.52)
	sword_model.add_child(sword_pivot)
	# Main INVISIBLE qui tient la poignée
	# Pas de cube de main : le bout de l'avant-bras tient la poignée (style Minecraft).
	# ── ÉPÉE (lame VERTICALE long en Y, visible en FPS) ──
	var blade = _mat(Color(0.78, 0.82, 0.88), 0.25, 0.9)
	var blade_edge = _mat(Color(0.95, 0.96, 1.0), 0.15, 0.95)
	var guard = _mat(Color(0.55, 0.42, 0.2), 0.4, 0.8)
	var handle = _mat(Color(0.3, 0.18, 0.1), 0.9)
	var pommel = _mat(Color(0.85, 0.65, 0.2), 0.3, 0.9)
	# Pommeau (boule en bas de la poignée, sous la main)
	_cube(sword_pivot, Vector3(0, -0.10, 0), Vector3(0.08, 0.08, 0.08), pommel)
	# Poignée (longue en Y, sort du dessus de la main)
	_cube(sword_pivot, Vector3(0, 0.05, 0), Vector3(0.05, 0.18, 0.07), handle)
	# Garde (croix horizontale en X, marque la séparation poignée/lame)
	_cube(sword_pivot, Vector3(0, 0.16, 0), Vector3(0.25, 0.05, 0.06), guard)
	# Lame (LONG EN Y, monte vers le haut — bien visible en FPS)
	_cube(sword_pivot, Vector3(0, 0.40, 0), Vector3(0.08, 0.45, 0.04), blade)
	# Arête lumineuse (fine bande qui brille au centre de la lame)
	_cube(sword_pivot, Vector3(0, 0.40, 0.02), Vector3(0.025, 0.45, 0.01), blade_edge)
	# Pointe (sommet de la lame, en haut)
	_cube(sword_pivot, Vector3(0, 0.65, 0), Vector3(0.05, 0.08, 0.04), blade_edge)
	sword_model.visible = false
	arm_pivot.add_child(fps_arms)

# Construit le modèle 3D voxel du joueur dans le monde.
# Style : Steve-like Minecraft mais dark fantasy avec armure noire/rouge.
# Visible en mode TPS, invisible en mode FPS (sinon on verrait son propre corps de l'intérieur).
# Le corps est attaché au CharacterBody3D donc il bouge naturellement avec le joueur.
func build_player_body():
	player_body = Node3D.new()
	player_body.name = "PlayerBody"
	add_child(player_body)
	# Hauteur de référence : la capsule de collision est de 1.8m de haut, centrée à Y=0.9.
	# Le modèle voxel fait 1m85 (taille humaine standard, type Steve Minecraft 1m80 + casque).
	# Pieds à Y=0, sommet du casque à Y=1.85.
	# Matériaux dark fantasy
	var armor = _mat(Color(0.18, 0.18, 0.20), 0.4, 0.7)  # Armure noire métallique
	var armor_red = _mat(Color(0.45, 0.10, 0.10), 0.5, 0.6)  # Détails rouges
	var skin = _mat(Color(0.55, 0.42, 0.34), 0.85)  # Peau tannée
	var pants = _mat(Color(0.12, 0.10, 0.08), 0.9)  # Pantalon cuir
	var boot = _mat(Color(0.25, 0.18, 0.10), 0.75)  # Bottes
	# ── TÊTE ──
	# Centre tête à Y=1.55 (était 1.65), hauteur 0.28 → top à 1.69
	_cube(player_body, Vector3(0, 1.55, 0), Vector3(0.28, 0.28, 0.28), skin)
	# Yeux rouges
	_cube(player_body, Vector3(0.075, 1.57, -0.145), Vector3(0.045, 0.035, 0.01), _mat(Color(0.9, 0.2, 0.2)))
	_cube(player_body, Vector3(-0.075, 1.57, -0.145), Vector3(0.045, 0.035, 0.01), _mat(Color(0.9, 0.2, 0.2)))
	# Casque (base) au-dessus de la tête, Y=1.74
	_cube(player_body, Vector3(0, 1.74, 0), Vector3(0.30, 0.07, 0.30), armor)
	# Pointes du casque (couronne) Y=1.80, hauteur 0.10 → top à 1.85 ✅
	_cube(player_body, Vector3(0.09, 1.80, 0), Vector3(0.04, 0.10, 0.04), armor_red)
	_cube(player_body, Vector3(-0.09, 1.80, 0), Vector3(0.04, 0.10, 0.04), armor_red)
	_cube(player_body, Vector3(0, 1.80, 0.09), Vector3(0.04, 0.10, 0.04), armor_red)
	_cube(player_body, Vector3(0, 1.80, -0.09), Vector3(0.04, 0.10, 0.04), armor_red)
	# ── TORSE (armure de plate) ──
	# Centre Y=1.18 (était 1.25), hauteur 0.47 → de 0.95 à 1.41
	_cube(player_body, Vector3(0, 1.18, 0), Vector3(0.52, 0.47, 0.28), armor)
	# Détail rouge sur la poitrine
	_cube(player_body, Vector3(0, 1.22, -0.145), Vector3(0.18, 0.14, 0.01), armor_red)
	# Ceinture
	_cube(player_body, Vector3(0, 0.90, 0), Vector3(0.55, 0.07, 0.30), _mat(Color(0.15, 0.10, 0.05), 0.9))
	# ── BRAS ──
	# Bras gauche (épaule + biceps + avant-bras)
	_cube(player_body, Vector3(-0.36, 1.32, 0), Vector3(0.17, 0.18, 0.18), armor)  # Épaule
	_cube(player_body, Vector3(-0.36, 1.11, 0), Vector3(0.14, 0.23, 0.14), armor)  # Biceps
	_cube(player_body, Vector3(-0.36, 0.89, 0), Vector3(0.12, 0.20, 0.12), skin)  # Avant-bras
	# Bras droit
	_cube(player_body, Vector3(0.36, 1.32, 0), Vector3(0.17, 0.18, 0.18), armor)
	_cube(player_body, Vector3(0.36, 1.11, 0), Vector3(0.14, 0.23, 0.14), armor)
	_cube(player_body, Vector3(0.36, 0.89, 0), Vector3(0.12, 0.20, 0.12), skin)
	# ── JAMBES ──
	# Cuisse Y=0.62 (était 0.65), hauteur 0.42
	_cube(player_body, Vector3(-0.14, 0.62, 0), Vector3(0.18, 0.42, 0.20), pants)
	_cube(player_body, Vector3(-0.14, 0.24, 0), Vector3(0.16, 0.32, 0.18), pants)  # Tibia
	_cube(player_body, Vector3(-0.14, 0.05, 0.04), Vector3(0.18, 0.10, 0.26), boot)  # Botte
	_cube(player_body, Vector3(0.14, 0.62, 0), Vector3(0.18, 0.42, 0.20), pants)
	_cube(player_body, Vector3(0.14, 0.24, 0), Vector3(0.16, 0.32, 0.18), pants)
	_cube(player_body, Vector3(0.14, 0.05, 0.04), Vector3(0.18, 0.10, 0.26), boot)
	# Caché visuellement par défaut (en FPS on ne se voit pas soi-même),
	# MAIS on garde la projection d'ombre activée pour avoir une vraie ombre humaine
	# au sol (sinon l'ombre FPS = juste bras+arme = silhouette ridicule).
	# SHADOWS_ONLY = mesh invisible mais ombre projetée normalement.
	for child in player_body.get_children():
		if child is MeshInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	player_body.visible = true  # Visible pour que SHADOWS_ONLY fonctionne

# Bascule entre la vue FPS et la vue 3ème personne.
# Appelé par le HUD via le bouton dédié. Permet de voir son perso de l'extérieur
# (utile pour debug visuel des bras/armes ET futur mode emote).
func toggle_tps_view() -> void:
	tps_active = not tps_active
	if tps_active:
		tps_camera.current = true
		# Cache les bras FPS (sinon ils flotteraient dans le monde devant la caméra TPS)
		if fps_arms:
			fps_arms.visible = false
		# En TPS, le player_body devient pleinement visible (pas seulement son ombre)
		if player_body:
			for child in player_body.get_children():
				if child is MeshInstance3D:
					child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		camera.current = true
		if fps_arms:
			fps_arms.visible = true
		# En FPS, le player_body redevient SHADOWS_ONLY (ombre seule, mesh invisible)
		if player_body:
			for child in player_body.get_children():
				if child is MeshInstance3D:
					child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

# Active/désactive le mode ZOOM (ADS - Aim Down Sights).
# Appelé par le bouton ZOOM du HUD. Le zoom est ignoré si l'arme courante est l'épée
# (filtre dans _physics_process via can_zoom).
func toggle_zoom() -> void:
	zoom_active = not zoom_active

# Active le modèle 3D de l'arme donnée, cache les autres.
# Appelé par WeaponController.set_weapon() au switch.
func show_weapon_model(weapon_id: String) -> void:
	if xbow_model != null:
		xbow_model.visible = (weapon_id == "crossbow")
	if sword_model != null:
		sword_model.visible = (weapon_id == "sword")

func _input(event):
	if event is InputEventMouseMotion:
		var sh: float = Settings.get_value("cam_sens_h", mouse_sens)
		var sv: float = Settings.get_value("cam_sens_v", mouse_sens)
		rotation.y -= event.relative.x * sh
		cam_pitch -= event.relative.y * sv
		cam_pitch = clamp(cam_pitch, -1.2, 1.0)
		camera.rotation.x = cam_pitch

func _unhandled_input(event):
	if event is InputEventScreenTouch:
		var vp = get_viewport().get_visible_rect().size
		# Zone d'attaque : coin bas-droit, rayon 120px autour du bouton attaque.
		# Les touches dans cette zone sont gérées par le HUD (tap = attaque).
		# On les ignore ici pour éviter que le joystick "look" intercepte le tap
		# et fasse bouger la caméra en même temps que l'attaque.
		var in_atk_zone = event.position.distance_to(Vector2(vp.x - 180, vp.y - 360)) <= 120
		if event.pressed:
			if in_atk_zone:
				return
			if event.position.x < vp.x * 0.4:
				move_tid = event.index
				move_origin = event.position
				move_vec = Vector2.ZERO
			else:
				look_tid = event.index
		else:
			if event.index == move_tid: move_tid = -1; move_vec = Vector2.ZERO
			if event.index == look_tid: look_tid = -1
	if event is InputEventScreenDrag:
		if event.index == move_tid:
			var d = event.position - move_origin
			if d.length() > 60: d = d.normalized() * 60
			move_vec = d / 60
		if event.index == look_tid:
			var sh: float = Settings.get_value("cam_sens_h", touch_sens)
			var sv: float = Settings.get_value("cam_sens_v", touch_sens)
			rotation.y -= event.relative.x * sh
			cam_pitch -= event.relative.y * sv
			cam_pitch = clamp(cam_pitch, -1.2, 1.0)
			camera.rotation.x = cam_pitch
			# NOTE : l'ancien auto-do_atk() sur swipe caméra a été retiré.
			# Il déclenchait des attaques involontaires en tournant la caméra,
			# et entrait en conflit avec le nouveau système de swipe HUD.

func _physics_process(delta):
	# === ZOOM (ADS) : lerp progressif vers la pose cible + FOV ===
	# zoom_active=true → zoom_t monte vers 1, sinon descend vers 0.
	# zoom_t=0 → live_* utilisé tel quel. zoom_t=1 → ZOOM_* utilisé.
	# Le zoom ne s'active que si l'arbalète est l'arme courante (pas l'épée).
	var can_zoom = (xbow_model != null and xbow_model.visible)
	var target_t = 1.0 if (zoom_active and can_zoom) else 0.0
	zoom_t = move_toward(zoom_t, target_t, ZOOM_SPEED * delta)
	# Calcule les valeurs effectives en lerp(live, ZOOM, zoom_t)
	var eff_yaw      = lerp(live_yaw,        ZOOM_R_YAW,   zoom_t)
	var eff_sh_x     = lerp(live_sh_x_rot,   ZOOM_R_SH_X,  zoom_t)
	var eff_sh_z     = lerp(live_sh_z_rot,   ZOOM_R_SH_Z,  zoom_t)
	var eff_f_yaw    = lerp(live_f_yaw,      ZOOM_R_F_YAW, zoom_t)
	var eff_f_x      = lerp(live_x_rot,      ZOOM_R_F_X,   zoom_t)
	var eff_f_z      = lerp(live_z_rot,      ZOOM_R_F_Z,   zoom_t)
	var eff_h_yaw    = lerp(live_h_yaw,      ZOOM_R_H_YAW, zoom_t)
	var eff_h_x      = lerp(live_hand_x_rot, ZOOM_R_H_X,   zoom_t)
	var eff_h_z      = lerp(live_hand_z_rot, ZOOM_R_H_Z,   zoom_t)
	var eff_l_yaw    = lerp(live_l_yaw,        ZOOM_L_YAW,   zoom_t)
	var eff_l_sh_x   = lerp(live_l_sh_x_rot,   ZOOM_L_SH_X,  zoom_t)
	var eff_l_sh_z   = lerp(live_l_sh_z_rot,   ZOOM_L_SH_Z,  zoom_t)
	var eff_l_f_yaw  = lerp(live_l_f_yaw,      ZOOM_L_F_YAW, zoom_t)
	var eff_l_f_x    = lerp(live_l_x_rot,      ZOOM_L_F_X,   zoom_t)
	var eff_l_f_z    = lerp(live_l_z_rot,      ZOOM_L_F_Z,   zoom_t)
	var eff_l_h_yaw  = lerp(live_l_h_yaw,      ZOOM_L_H_YAW, zoom_t)
	var eff_l_h_x    = lerp(live_l_hand_x_rot, ZOOM_L_H_X,   zoom_t)
	var eff_l_h_z    = lerp(live_l_hand_z_rot, ZOOM_L_H_Z,   zoom_t)
	var eff_arm_z    = lerp(live_arm_z,    ZOOM_ARM_Z,  zoom_t)
	var eff_rig_x    = lerp(live_rig_x,    ZOOM_RIG_X,  zoom_t)
	var eff_rig_y    = lerp(live_rig_y,    ZOOM_RIG_Y,  zoom_t)
	var eff_rig_z    = lerp(live_rig_z,    ZOOM_RIG_Z,  zoom_t)
	var eff_rig_pit  = lerp(live_rig_pitch, ZOOM_R_PIT, zoom_t)
	# FOV de la caméra : effet "lunette" qui grossit la cible
	if camera:
		camera.fov = lerp(FOV_NORMAL, FOV_ZOOM, zoom_t)
	# === APPLIQUE LES RÉGLAGES DU BRAS chaque frame ===
	# (modifie les const en haut du fichier pour ajuster)
	# === APPLIQUE LES ANGLES LIVE AU RIG FPS chaque frame ===
	# Quand tu modifies le panneau, ça update à la fois le mannequin (extérieur)
	# ET ton rig FPS (vu en 1ère personne). Comme ça les deux vues sont cohérentes.
	if arm_r_pivot_ref:
		arm_r_pivot_ref.position = Vector3(live_spread, ARM_PIVOT_Y, ARM_PIVOT_Z)
		arm_r_pivot_ref.rotation = Vector3(eff_sh_x, eff_yaw, eff_sh_z)
	if shoulder_r_cube_ref:
		shoulder_r_cube_ref.position.x = live_spread
	if shoulder_l_cube_ref:
		shoulder_l_cube_ref.position.x = -live_spread
	if forearm_x_ref:
		forearm_x_ref.rotation = Vector3(eff_f_x, eff_f_yaw, eff_f_z)
	if forearm_s_ref:
		forearm_s_ref.rotation = Vector3(eff_f_x, eff_f_yaw, eff_f_z)
	if hand_pivot_ref:
		hand_pivot_ref.rotation = Vector3(eff_h_x, eff_h_yaw, eff_h_z)
	# Position Z de l'arme : 0.42 (offset de base pour compenser hand_pivot) + eff_arm_z (zoom-aware)
	if xbow_model:
		xbow_model.position.z = 0.42 + eff_arm_z
	if sword_model:
		sword_model.position.z = 0.42 + eff_arm_z
	# === BRAS GAUCHE : valeurs eff_l_* (lerp live_l_* → ZOOM_L_*) ===
	if arm_l_pivot_ref:
		arm_l_pivot_ref.position = Vector3(-live_spread, ARM_L_PIVOT_Y, ARM_L_PIVOT_Z)
		arm_l_pivot_ref.rotation = Vector3(eff_l_sh_x, eff_l_yaw, eff_l_sh_z)
	if forearm_l_ref:
		forearm_l_ref.rotation = Vector3(eff_l_f_x, eff_l_f_yaw, eff_l_f_z)
	if hand_l_pivot_ref:
		hand_l_pivot_ref.rotation = Vector3(eff_l_h_x, eff_l_h_yaw, eff_l_h_z)
	# === PHOTO MODE : freeze + fly cam (joystick = mouvement libre 3D, pas de gravité) ===
	if photo_mode:
		var fly_iv = Vector2.ZERO
		if move_tid >= 0: fly_iv = move_vec
		var fly_dir = (transform.basis * Vector3(fly_iv.x, 0, fly_iv.y)).normalized()
		# Vitesse de vol modérée pour cadrer précisément
		velocity = fly_dir * 4.0
		move_and_slide()
		# atk_cd / xbow_cd / combo_t continuent de descendre normalement
		if atk_cd > 0: atk_cd -= delta
		if xbow_cd_timer > 0: xbow_cd_timer -= delta
		if combo_t > 0: combo_t -= delta
		return  # skip tout le reste : pas de sprint, pas de gravité
	if not is_on_floor(): velocity.y -= gravity_force * delta
	var iv = Vector2.ZERO
	if move_tid >= 0: iv = move_vec
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z): iv.y -= 1
	if Input.is_key_pressed(KEY_S): iv.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q): iv.x -= 1
	if Input.is_key_pressed(KEY_D): iv.x += 1
	iv = iv.limit_length(1.0)
	# === DÉTECTION SPRINT (avec hystérésis pour éviter vibration) ===
	# Entre en sprint à 0.85, sort à 0.65 — empêche le flip-flop autour d'un seuil unique.
	if iv.length() > SPRINT_ENTER:
		is_sprinting = true
	elif iv.length() < SPRINT_EXIT:
		is_sprinting = false
	var sprint_target := SPRINT_TARGET if is_sprinting else 1.0
	sprint_factor = lerp(sprint_factor, sprint_target, 6.0 * delta)
	var dir = (transform.basis * Vector3(iv.x, 0, iv.y)).normalized()
	if dir: velocity.x = dir.x * speed * sprint_factor; velocity.z = dir.z * speed * sprint_factor
	else: velocity.x = move_toward(velocity.x, 0, speed*5*delta); velocity.z = move_toward(velocity.z, 0, speed*5*delta)
	move_and_slide()
	if atk_cd > 0: atk_cd -= delta
	if xbow_cd_timer > 0: xbow_cd_timer -= delta
	if combo_t > 0: combo_t -= delta
	else: combo = 0
	# === ANIMATIONS FPS — BOBBING + IDLE BREATHING (style TaCZ) ===
	# Anim de marche : oscillation vertical + horizontal + léger tilt rotation pour le feel.
	# Anim idle : respiration lente (très subtil, juste pour ne pas que ce soit figé).
	# Amplitudes augmentées vs avant pour un rendu plus "vivant" comme dans les FPS modernes.
	# === WEAPON SWAY (lag caméra) ===
	# Calcule le delta de rotation entre cette frame et la précédente, l'accumule
	# dans sway_*_vel, et le décroît doucement vers zéro. C'est ce delta accumulé
	# qu'on applique visuellement à fps_arms (en + du bobbing).
	var d_yaw = rotation.y - prev_yaw
	# Gestion du wrap-around (si rotation.y traverse ±PI)
	if d_yaw > PI: d_yaw -= TAU
	elif d_yaw < -PI: d_yaw += TAU
	var d_pitch = cam_pitch - prev_pitch
	prev_yaw = rotation.y
	prev_pitch = cam_pitch
	sway_yaw_vel += d_yaw
	sway_pitch_vel += d_pitch
	# Décroît vers zéro plus vite (amortit les micro-mouvements de caméra qui causent la vibration)
	sway_yaw_vel = lerp(sway_yaw_vel, 0.0, 12.0 * delta)
	sway_pitch_vel = lerp(sway_pitch_vel, 0.0, 12.0 * delta)
	# Deadzone : les valeurs très petites passent à 0 (anti-vibration)
	if abs(sway_yaw_vel) < 0.002: sway_yaw_vel = 0.0
	if abs(sway_pitch_vel) < 0.002: sway_pitch_vel = 0.0
	# Clamp pour éviter des sway extrêmes sur des mouvements caméra brusques
	sway_yaw_vel = clamp(sway_yaw_vel, -0.2, 0.2)
	sway_pitch_vel = clamp(sway_pitch_vel, -0.2, 0.2)

	if fps_arms and atk_anim <= 0:
		var bob_y := 0.0
		var bob_x := 0.0
		var bob_zrot := 0.0
		if iv.length() > 0.1:
			# WALK/SPRINT BOBBING : amplitude monte avec sprint, fréquence aussi.
			# Phase accumulée (pas t*freq) pour éviter sauts de phase quand freq change.
			var amp = sprint_factor   # 1.0 walk → 1.2 sprint
			var freq = 1.0 + (sprint_factor - 1.0) * 1.0
			bob_phase_fast += delta * 8.0 * freq
			bob_phase_slow += delta * 4.0 * freq
			bob_y = sin(bob_phase_fast) * 0.025 * amp
			bob_x = sin(bob_phase_slow) * 0.012 * amp
			bob_zrot = sin(bob_phase_slow) * 0.02 * amp
		else:
			# IDLE BREATHING : très subtil, freq fixe (pas de sprint en idle)
			bob_phase_fast += delta * 1.5
			bob_phase_slow += delta * 1.0
			bob_y = sin(bob_phase_fast) * 0.006
			bob_x = sin(bob_phase_slow) * 0.003
			bob_zrot = sin(bob_phase_fast) * 0.004
		# Bobbing seul (sway désactivé car causait vibrations en tournant la caméra).
		# + Offset live du panneau (live_rig_*) pour ajuster la position du rig entier.
		fps_arms.position.y = bob_y + eff_rig_y
		fps_arms.position.x = bob_x + eff_rig_x
		fps_arms.position.z = eff_rig_z
		fps_arms.rotation.x = eff_rig_pit
		fps_arms.rotation.z = bob_zrot
	# === BOBBING INDÉPENDANT BRAS GAUCHE (déphasage 180°) ===
	# Le bras gauche balance en opposition de phase avec le droit, comme une
	# démarche humaine naturelle (bras opposés synchronisés). Quand le droit
	# monte, le gauche descend. Subtil mais ça enlève l'effet "pantin rigide".
	if arm_l_pivot_ref and atk_anim <= 0:
		if iv.length() > 0.1:
			arm_l_pivot_ref.rotation.x = sin(bob_phase_fast + PI) * 0.12 * sprint_factor
		else:
			arm_l_pivot_ref.rotation.x = sin(bob_phase_slow) * 0.02
	elif arm_l_pivot_ref:
		arm_l_pivot_ref.rotation.x = 0
	# === ROTATION X COMBINÉE : attack + sprint dip — SUR BRAS DROIT UNIQUEMENT ===
	# Avant : appliqué à fps_arms (les 2 bras swingaient ensemble pendant tir/sprint).
	# Maintenant : appliqué à arm_r_pivot seulement (bras qui tient l'arme).
	# → Le bras gauche reste stable et indépendant lors de tirs/swings/sprint.
	var rot_x := eff_sh_x  # base rotation X de l'épaule (panneau, lerp avec ZOOM)
	if atk_anim > 0:
		atk_anim -= delta
		if atk_anim < 0: atk_anim = 0
		rot_x += -0.5 * (atk_anim / 0.2)
	# Sprint dip : l'arme penche vers le bas pendant le sprint
	rot_x += (sprint_factor - 1.0) / (SPRINT_TARGET - 1.0) * SPRINT_DIP
	if arm_r_pivot_ref:
		arm_r_pivot_ref.rotation.x = rot_x
		arm_r_pivot_ref.rotation.z = eff_sh_z
	if fps_arms:
		fps_arms.rotation.x = eff_rig_pit  # Reset avec valeur zoom-aware
	# RECOIL ARBALÈTE : l'arme recule + s'incline vers le haut au tir (style TaCZ).
	# xbow_recoil est mis à 0.8 par do_shoot(), décroît à 0 sur ~0.2 sec.
	# On applique sur xbow_model uniquement (pas tout le rig) pour que seule l'arme bouge.
	if xbow_recoil > 0:
		xbow_recoil -= delta * 4.0
		if xbow_recoil < 0: xbow_recoil = 0
		if xbow_model != null and xbow_model.visible:
			# Recule sur Z (vers la caméra) + s'incline vers le haut sur X
			# Base position Z = 0.42 (offset hand_pivot) + eff_arm_z (panneau + zoom) + recul
			xbow_model.position.z = 0.42 + eff_arm_z + xbow_recoil * 0.15
			xbow_model.rotation.x = xbow_recoil * 0.25
	elif xbow_model != null and xbow_model.visible:
		# Reset à position de base quand pas de recoil actif (avec zoom)
		xbow_model.position.z = 0.42 + eff_arm_z
		xbow_model.rotation.x = 0
	# === SYSTÈME DE COMBOS ÉPÉE ===
	# 3 styles qui alternent à chaque tap : Conan → Katana → Overhead → Conan...
	# Chaque style a sa propre courbe (amplitude, axe dominant, timing).
	# Reset à 0 après SWORD_COMBO_RESET secondes sans taper.
	# Timer de reset : s'incrémente quand on tape pas, reset l'index si dépasse la limite
	if sword_swing <= 0:
		sword_combo_timer += delta
		if sword_combo_timer >= SWORD_COMBO_RESET and sword_combo_index != 1:
			sword_combo_index = 1  # Reset au Katana (style par défaut tap simple)
	if sword_swing > 0 and sword_pivot != null:
		sword_swing -= delta * 2.5
		if sword_swing < 0: sword_swing = 0
		var s = sword_swing
		var x_rot := 0.0
		var y_rot := 0.0
		var z_rot := 0.0
		# Dispatch selon le style de combo actuel
		match sword_combo_index:
			0:
				# === STYLE 1 : CONAN SLASH ===
				# Coup latéral ample et lourd. Wind-up loin à droite, strike massif
				# à gauche (~85°), plongée marquée. Sensation de puissance brute.
				if s > 0.85:
					var p = (1.0 - s) / 0.15
					x_rot = lerp(0.0, -0.4, p)   # Lame lève en arrière
					y_rot = lerp(0.0, 0.8, p)    # Recule loin à droite
					z_rot = lerp(0.0, 0.4, p)
				elif s > 0.5:
					var p = (0.85 - s) / 0.35
					x_rot = lerp(-0.4, 0.5, p)   # Plongée lourde
					y_rot = lerp(0.8, -1.5, p)   # ~85° d'amplitude
					z_rot = lerp(0.4, -0.6, p)
				else:
					var p = s / 0.5
					x_rot = lerp(0.0, 0.5, p)
					y_rot = lerp(0.0, -1.5, p)
					z_rot = lerp(0.0, -0.6, p)
			1:
				# === STYLE 2 : KATANA FLICK ===
				# Fouetté sec et rapide. Petite amplitude (~45°), pas de wind-up visible,
				# strike instantané, recovery rapide. Sensation de précision et vitesse.
				if s > 0.92:
					# Wind-up quasi-inexistant : juste un petit recul
					var p = (1.0 - s) / 0.08
					y_rot = lerp(0.0, 0.3, p)
				elif s > 0.6:
					# Strike instantané
					var p = (0.92 - s) / 0.32
					y_rot = lerp(0.3, -0.8, p)   # Plus sec, plus court
					x_rot = lerp(0.0, 0.15, p)   # Plongée légère
					z_rot = lerp(0.0, -0.2, p)
				else:
					# Recovery très rapide
					var p = s / 0.6
					x_rot = lerp(0.0, 0.15, p)
					y_rot = lerp(0.0, -0.8, p)
					z_rot = lerp(0.0, -0.2, p)
			2:
				# === STYLE 3 : OVERHEAD ===
				# Coup vertical de haut en bas. L'épée lève au-dessus de la tête
				# (rotation X forte) puis retombe violemment. Pas de rotation Y.
				# Sensation d'écrasement / finisher.
				if s > 0.75:
					# Wind-up : lame lève haut en arrière
					var p = (1.0 - s) / 0.25
					x_rot = lerp(0.0, -1.4, p)   # Haut derrière
					z_rot = lerp(0.0, 0.1, p)
				elif s > 0.4:
					# Strike : chute verticale violente
					var p = (0.75 - s) / 0.35
					x_rot = lerp(-1.4, 0.8, p)   # Grosse amplitude verticale
					z_rot = lerp(0.1, -0.15, p)
				else:
					# Recovery
					var p = s / 0.4
					x_rot = lerp(0.0, 0.8, p)
					z_rot = lerp(0.0, -0.15, p)
			3:
				# === STYLE 4 : UPPERCUT ===
				# Coup remontant, inverse de l'Overhead : l'épée part du bas,
				# remonte violemment vers le haut. Parfait pour cueillir un adversaire
				# qui esquive vers le haut, ou un ennemi plus petit / au sol.
				if s > 0.75:
					# Wind-up : lame plonge vers le bas (prise d'élan)
					var p = (1.0 - s) / 0.25
					x_rot = lerp(0.0, 0.8, p)    # Bas devant
					z_rot = lerp(0.0, -0.15, p)
				elif s > 0.4:
					# Strike : remontée violente
					var p = (0.75 - s) / 0.35
					x_rot = lerp(0.8, -1.2, p)   # Vers le haut
					z_rot = lerp(-0.15, 0.1, p)
				else:
					# Recovery
					var p = s / 0.4
					x_rot = lerp(0.0, -1.2, p)
					z_rot = lerp(0.0, 0.1, p)
		sword_pivot.rotation.x = x_rot
		sword_pivot.rotation.y = y_rot
		sword_pivot.rotation.z = z_rot
		# NOTE : sword_combo_index reste fixé à 1 (Katana) pour l'instant.
		# Les 3 autres styles (Conan/Overhead/Uppercut) sont codés ci-dessus mais
		# inutilisés tant qu'aucun système de déclenchement n'est branché
		# (à venir : 2 boutons attaque, ou direction caméra + tap, etc.).
	elif sword_pivot != null and sword_pivot.rotation != Vector3.ZERO:
		sword_pivot.rotation = Vector3.ZERO
	# Détection + attraction + ramassage des cubes de loot dans un rayon
	_check_loot_pickup(delta)
	# Détection des tables de craft à proximité → prompt HUD
	_check_craft_stations()

func do_atk():
	if atk_cd > 0: return
	atk_cd = 0.4; atk_anim = 0.2; combo += 1; combo_t = 1.5
	# Déclenche l'animation de swing si l'épée est active, avance l'index de combo
	if sword_model != null and sword_model.visible:
		sword_swing = 1.0
		# Si le combo a été trop long à reprendre, il a déjà été reset par _physics_process.
		# Sinon, on passe au style suivant dans la séquence.
		sword_combo_timer = 0.0
	var main = get_parent()
	var nd = 4.0; var nt = null
	for e in main.enemies:
		if is_instance_valid(e):
			var d2 = global_position.distance_to(e.global_position)
			if d2 < nd: nd = d2; nt = e
	for obj in main.world_objects:
		if is_instance_valid(obj) and obj.has_meta("hp"):
			var d2 = global_position.distance_to(obj.global_position)
			if d2 < nd: nd = d2; nt = obj
	if nt:
		if nt is CharacterBody3D: nt.take_damage(get_dmg(), global_position)
		elif nt.has_meta("type"): harvest(nt, nt.get_meta("type"))

func get_dmg() -> int:
	return 5 + tier * 5

func do_shoot():
	if xbow_cd_timer > 0 or not has_xbow: return
	xbow_cd_timer = xbow_cd
	atk_anim = 0.15
	xbow_recoil = 0.8
	# Lecture des stats depuis la WeaponData active si dispo (système nouveau),
	# sinon fallback sur les variables hardcodées (compat).
	var active_dmg: int = xbow_dmg
	var active_range: float = xbow_range
	if weapon_inventory != null:
		var w = weapon_inventory.get_current()
		if w != null:
			active_dmg = w.damage
			active_range = w.range_max
	if shoot_sfx: shoot_sfx.play()
	shoot_ray.force_raycast_update()
	var hit_pos: Vector3
	var hit_target = null
	var did_hit := false
	# Ces deux vars capturent la position LOCALE du hit dans body_root de l'ennemi
	# AVANT take_damage (qui déclenche un knockback qui déplace l'ennemi). Sans ça,
	# la flèche arrive à hit_pos world mais l'ennemi a déjà bougé → flèche à côté.
	var attach_point: Node3D = null
	var local_hit := Vector3.ZERO
	if shoot_ray.is_colliding():
		hit_pos = shoot_ray.get_collision_point()
		var target = shoot_ray.get_collider()
		# Capture l'attach point AVANT take_damage pour préserver la position exacte
		if target != null and is_instance_valid(target) and target.has_method("get_bolt_attach"):
			var ap = target.get_bolt_attach()
			if ap != null and is_instance_valid(ap):
				attach_point = ap
				local_hit = ap.to_local(hit_pos)
		if target.has_method("take_damage"):
			target.take_damage(active_dmg, global_position)
			get_parent().get_node("HUD").hit_timer = 0.3
			did_hit = true
			hit_target = target
			# Si ce tir vient de tuer l'ennemi, take_damage a appelé die() qui a créé
			# le ragdoll_torso et queue_free(self). body_root va disparaître à la fin
			# de la frame → rediriger la flèche vers torso_rb (qui survit dans la scène).
			if target.has_method("get_ragdoll_torso"):
				var rt = target.get_ragdoll_torso()
				if rt != null and is_instance_valid(rt):
					# Convertir local_hit du frame body_root vers frame torso_rb via world coords
					if attach_point != null and is_instance_valid(attach_point):
						var world_hit = attach_point.to_global(local_hit)
						local_hit = rt.to_local(world_hit)
					else:
						local_hit = rt.to_local(hit_pos)
					attach_point = rt
	else:
		hit_pos = camera.global_position + camera.global_transform.basis * Vector3(0, 0, -active_range)
	spawn_bolt(hit_pos, hit_target, attach_point, local_hit)
	if did_hit:
		spawn_impact(hit_pos)

# Change le son de tir (appelé par WeaponController.set_weapon au switch d'arme).
# Permet d'avoir un son différent selon l'arme équipée sans recharger manuellement.
func set_weapon_sound(stream: AudioStream, volume_db: float = -12.0) -> void:
	if shoot_sfx == null or stream == null:
		return
	shoot_sfx.stream = stream
	shoot_sfx.volume_db = volume_db

func spawn_bolt(end_pos: Vector3, target = null, attach_point: Node3D = null, local_hit: Vector3 = Vector3.ZERO):
	var start_world = camera.global_position + camera.global_transform.basis * Vector3(0.15, -0.15, -1.0)
	var bolt = Node3D.new()
	# APPROCHE : la flèche vole en WORLD dans la scène principale (pas attachée à l'ennemi).
	# À l'arrivée elle se reparent à attach_point (body_root si vivant, torso_rb si mort)
	# et snap à local_hit. Comme ça : (a) vol visuellement correct, (b) position finale
	# exacte sur le corps peu importe knockback/mort, (c) pas d'orphelin si ennemi meurt.
	get_parent().add_child(bolt)
	bolt.global_position = start_world
	bolt.look_at(end_pos)
	# Voxel bolt — cubes only
	_cube(bolt, Vector3(0, 0, 0), Vector3(0.04, 0.04, 0.5), _mat(Color(0.3, 0.2, 0.1)))
	_cube(bolt, Vector3(0, 0, -0.28), Vector3(0.05, 0.05, 0.08), _mat(Color(0.5, 0.5, 0.52), 0.3, 0.7))
	_cube(bolt, Vector3(0, 0, 0.22), Vector3(0.12, 0.02, 0.08), _mat(Color(0.7, 0.65, 0.5)))
	_cube(bolt, Vector3(0, 0, 0.22), Vector3(0.02, 0.12, 0.08), _mat(Color(0.7, 0.65, 0.5)))
	# Fly then stick forever (Minecraft style)
	var dist = start_world.distance_to(end_pos)
	var fly_time = clamp(dist / 80.0, 0.05, 0.25)
	var tw = create_tween()
	tw.tween_property(bolt, "global_position", end_pos, fly_time)
	# À l'arrivée : reparent à attach_point (qui est body_root OU torso_rb selon kill ou pas)
	if attach_point != null and is_instance_valid(attach_point):
		var tgt = target
		var ap = attach_point
		var lh = local_hit
		tw.tween_callback(func():
			if not is_instance_valid(bolt): return
			if not is_instance_valid(ap): return
			# Reparenter en préservant le transform world (Godot 4 le fait par défaut)
			bolt.reparent(ap)
			# SNAP à la position LOCALE exacte du hit sur le corps
			# (body_root pour vivant, torso_rb pour mort — les deux cas marchent)
			bolt.position = lh
			# Enfoncer 0.15m dans la direction du vol pour pénétrer le mesh visuel
			var pen_dir = -bolt.global_transform.basis.z
			bolt.global_position += pen_dir * 0.15
			# Enregistrer pour transfert au ragdoll si ennemi encore vivant
			# (si déjà mort, flèche déjà sur torso_rb, pas besoin)
			if is_instance_valid(tgt) and tgt.has_method("register_bolt"):
				tgt.register_bolt(bolt)
		)

func spawn_impact(pos: Vector3):
	for i in range(5):
		var p = MeshInstance3D.new()
		var pm = BoxMesh.new()
		pm.size = Vector3(0.06, 0.06, 0.06)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.2, 0.1, 1)
		mat.roughness = 0.9
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.material = mat
		p.mesh = pm
		get_parent().add_child(p)
		p.global_position = pos
		p.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var d = Vector3(randf_range(-1, 1), randf_range(0.4, 1.2), randf_range(-1, 1)).normalized()
		var tw = create_tween()
		tw.tween_property(p, "global_position", pos + d * randf_range(0.4, 0.9), 0.35)
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.35)
		tw.tween_callback(p.queue_free)

func harvest(obj, type: String):
	var h = obj.get_meta("hp") - 1
	obj.set_meta("hp", h)
	match type:
		"tree": inventory["wood"] += 1
		"rock": inventory["stone"] += 1
		"iron": inventory["iron"] += 1
	var tw = create_tween()
	tw.tween_property(obj, "scale", Vector3.ONE * 0.8, 0.05)
	tw.tween_property(obj, "scale", Vector3.ONE, 0.1)
	if h <= 0:
		match type:
			"tree": inventory["wood"] += 3
			"rock": inventory["stone"] += 2
			"iron": inventory["iron"] += 2
		get_parent().world_objects.erase(obj)
		obj.queue_free()

func take_damage(amount: int):
	if photo_mode: return  # invincible en mode photo
	hp -= amount; hp = max(0, hp)
	var hud = get_parent().get_node_or_null("HUD")
	if hud: hud.show_dmg_flash()
	if hp <= 0: get_parent().game_running = false

# Détection + attraction + ramassage des cubes de loot.
# Appelée à chaque frame par _physics_process.
# - Parcourt les nodes du groupe "loot" (posés par enemy.gd _spawn_loot_drop)
# - Si distance < LOOT_PICKUP_RADIUS ET pas déjà en cours d'attraction →
#   on lance un tween qui attire le cube vers le player
# - À la fin du tween, le cube est "ramassé" : incrément inventory + queue_free
func _check_loot_pickup(_delta: float):
	var loots = get_tree().get_nodes_in_group("loot")
	for cube in loots:
		if not is_instance_valid(cube):
			continue
		# Déjà en cours d'attraction → ignorer
		if cube.get_meta("picked", false):
			continue
		# Distance player ↔ cube (ignore Y pour éviter les pb si cube au sol)
		var dx = cube.global_position.x - global_position.x
		var dz = cube.global_position.z - global_position.z
		var dist = sqrt(dx * dx + dz * dz)
		if dist < LOOT_PICKUP_RADIUS:
			_start_loot_magnet(cube)

# Lance le tween d'attraction d'un cube de loot vers le player.
# Le cube vole vers la poitrine du player en LOOT_MAGNET_DURATION secondes,
# avec un léger shrink final. À la fin : incrément inventory + queue_free.
func _start_loot_magnet(cube: Node3D):
	cube.set_meta("picked", true)
	# Stopper tout tween en cours sur le cube (rotation au sol) pour éviter conflit
	# Note : on crée un nouveau tween qui remplace l'ancien (Godot gère ça)
	var target_pos = global_position + Vector3(0, 1.0, 0)  # Poitrine
	var tw = cube.create_tween()
	tw.set_parallel(true)
	tw.tween_property(cube, "global_position", target_pos, LOOT_MAGNET_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(cube, "scale", Vector3.ONE * 0.3, LOOT_MAGNET_DURATION).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		if not is_instance_valid(cube):
			return
		# Lire le type de loot et incrémenter le bon compteur inventory
		var loot_type = cube.get_meta("loot_type", "")
		if LOOT_TYPE_TO_INV.has(loot_type):
			var inv_key = LOOT_TYPE_TO_INV[loot_type]
			inventory[inv_key] += 1
		cube.queue_free()
	)

# Détecte la table de craft la plus proche du player.
# Appelée à chaque frame par _physics_process.
# - Parcourt les nodes du groupe "craft_station" (posés par main.gd)
# - Trouve la plus proche (distance horizontale XZ)
# - Si dans CRAFT_DETECTION_RADIUS, affiche un prompt HUD adapté :
#     * Débloqué (kills >= seuil)  → "🔨 [Nom] — Tap Craft" en vert
#     * Verrouillé (kills < seuil) → "🔒 [N] kills requis ([Nom])" en orange
# - Sinon, masque le prompt.
func _check_craft_stations():
	var main = get_parent()
	var hud = main.get_node_or_null("HUD") if main else null
	if not hud:
		return
	var stations = get_tree().get_nodes_in_group("craft_station")
	var closest = null
	var closest_dist = 1e9
	for s in stations:
		if not is_instance_valid(s):
			continue
		var dx = s.global_position.x - global_position.x
		var dz = s.global_position.z - global_position.z
		var d = sqrt(dx * dx + dz * dz)
		if d < closest_dist:
			closest_dist = d
			closest = s
	# Trop loin → masquer le prompt
	if closest == null or closest_dist > CRAFT_DETECTION_RADIUS:
		hud.show_craft_prompt("", true)
		return
	# Construire le texte selon verrouillage
	var craft_type = closest.get_meta("craft_type", "")
	var kills_req = closest.get_meta("kills_required", 0)
	var station_name = CRAFT_STATION_NAMES.get(craft_type, craft_type.capitalize())
	if kills >= kills_req:
		# Débloqué
		hud.show_craft_prompt("🔨 " + station_name + " — Tap Craft", true)
	else:
		# Verrouillé : combien de kills restants
		var remaining = kills_req - kills
		hud.show_craft_prompt("🔒 " + str(remaining) + " kill(s) requis — " + station_name, false)
