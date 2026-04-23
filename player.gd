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
#   do_atk()                           → Attaque mêlée (épée, non utilisée actuellement)
#   get_dmg() -> int                   → Calcule dégâts mêlée selon combo
#   do_shoot()                         → Tir arbalète + raycast + spawn carreau
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
#   has_xbow (true)                    → Arbalète équipée
#   xbow_dmg (25) / xbow_range (40)    → Dégâts et portée arbalète
#   xbow_cd (1.2)                      → Cooldown entre tirs
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
var atk_anim := 0.0
var xbow_recoil := 0.0
var shoot_sfx: AudioStreamPlayer

@onready var camera: Camera3D = $Camera3D
@onready var arm_pivot: Node3D = $Camera3D/ArmPivot

func _ready():
	build_arms()
	shoot_ray = RayCast3D.new()
	shoot_ray.target_position = Vector3(0, 0, -xbow_range)
	shoot_ray.enabled = true
	camera.add_child(shoot_ray)
	shoot_sfx = AudioStreamPlayer.new()
	shoot_sfx.stream = load("res://sounds/xbow_shoot.wav")
	shoot_sfx.volume_db = -12.0
	add_child(shoot_sfx)

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

func build_arms():
	fps_arms = Node3D.new()
	var skin = _mat(Color(0.6, 0.48, 0.35), 0.85)
	var glove = _mat(Color(0.18, 0.13, 0.08), 0.9)
	var armor = _mat(Color(0.22, 0.22, 0.25), 0.4, 0.7)
	# Right arm (voxel blocky)
	_cube(fps_arms, Vector3(0.35, -0.25, -0.2), Vector3(0.16, 0.35, 0.16), armor)
	_cube(fps_arms, Vector3(0.35, -0.5, -0.35), Vector3(0.14, 0.3, 0.14), skin)
	_cube(fps_arms, Vector3(0.35, -0.7, -0.45), Vector3(0.16, 0.12, 0.18), glove)
	# Left arm
	_cube(fps_arms, Vector3(-0.35, -0.25, -0.2), Vector3(0.16, 0.35, 0.16), armor)
	_cube(fps_arms, Vector3(-0.35, -0.5, -0.35), Vector3(0.14, 0.3, 0.14), skin)
	_cube(fps_arms, Vector3(-0.35, -0.7, -0.45), Vector3(0.16, 0.12, 0.18), glove)
	# Crossbow — voxel
	if has_xbow:
		var wood = _mat(Color(0.3, 0.2, 0.1), 0.9)
		var wood_dark = _mat(Color(0.22, 0.14, 0.07), 0.9)
		var metal = _mat(Color(0.4, 0.4, 0.45), 0.3, 0.8)
		var string = _mat(Color(0.7, 0.65, 0.5), 0.6)
		# Main body (stock)
		_cube(fps_arms, Vector3(0.35, -0.55, -0.55), Vector3(0.08, 0.1, 0.55), wood)
		_cube(fps_arms, Vector3(0.35, -0.48, -0.55), Vector3(0.1, 0.07, 0.5), wood_dark)
		# Trigger guard
		_cube(fps_arms, Vector3(0.35, -0.62, -0.4), Vector3(0.05, 0.08, 0.05), metal)
		# Grip
		_cube(fps_arms, Vector3(0.35, -0.65, -0.35), Vector3(0.08, 0.15, 0.1), wood_dark)
		# Bow horizontal arms
		_cube(fps_arms, Vector3(0.16, -0.48, -0.78), Vector3(0.2, 0.06, 0.06), wood)
		_cube(fps_arms, Vector3(0.54, -0.48, -0.78), Vector3(0.2, 0.06, 0.06), wood)
		# Bow tips
		_cube(fps_arms, Vector3(0.06, -0.48, -0.78), Vector3(0.04, 0.1, 0.06), wood_dark)
		_cube(fps_arms, Vector3(0.64, -0.48, -0.78), Vector3(0.04, 0.1, 0.06), wood_dark)
		# Strings
		_cube(fps_arms, Vector3(0.22, -0.48, -0.72), Vector3(0.015, 0.015, 0.15), string)
		_cube(fps_arms, Vector3(0.48, -0.48, -0.72), Vector3(0.015, 0.015, 0.15), string)
		# Bolt visible in groove
		_cube(fps_arms, Vector3(0.35, -0.44, -0.65), Vector3(0.02, 0.02, 0.3), _mat(Color(0.35, 0.25, 0.15)))
		# Metal accents
		_cube(fps_arms, Vector3(0.35, -0.48, -0.78), Vector3(0.14, 0.09, 0.04), metal)
	arm_pivot.add_child(fps_arms)

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
		if event.pressed:
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
			if event.relative.length() > 5.0 and atk_cd <= 0: do_atk()

func _physics_process(delta):
	if not is_on_floor(): velocity.y -= gravity_force * delta
	var iv = Vector2.ZERO
	if move_tid >= 0: iv = move_vec
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z): iv.y -= 1
	if Input.is_key_pressed(KEY_S): iv.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q): iv.x -= 1
	if Input.is_key_pressed(KEY_D): iv.x += 1
	iv = iv.limit_length(1.0)
	var dir = (transform.basis * Vector3(iv.x, 0, iv.y)).normalized()
	if dir: velocity.x = dir.x * speed; velocity.z = dir.z * speed
	else: velocity.x = move_toward(velocity.x, 0, speed*5*delta); velocity.z = move_toward(velocity.z, 0, speed*5*delta)
	move_and_slide()
	if atk_cd > 0: atk_cd -= delta
	if xbow_cd_timer > 0: xbow_cd_timer -= delta
	if combo_t > 0: combo_t -= delta
	else: combo = 0
	if fps_arms and atk_anim <= 0:
		var t2 = Time.get_ticks_msec() / 1000.0
		if iv.length() > 0.1:
			fps_arms.position.y = sin(t2 * 8) * 0.02
			fps_arms.position.x = sin(t2 * 4) * 0.01
		else:
			fps_arms.position.y = sin(t2 * 2) * 0.005; fps_arms.position.x = 0
	if atk_anim > 0:
		atk_anim -= delta
		fps_arms.rotation.x = -0.5 * (atk_anim / 0.2)
		if atk_anim <= 0: fps_arms.rotation.x = 0
	if xbow_recoil > 0:
		xbow_recoil -= delta * 4.0
		if xbow_recoil < 0: xbow_recoil = 0
	# Détection + attraction + ramassage des cubes de loot dans un rayon
	_check_loot_pickup(delta)
	# Détection des tables de craft à proximité → prompt HUD
	_check_craft_stations()

func do_atk():
	if atk_cd > 0: return
	atk_cd = 0.4; atk_anim = 0.2; combo += 1; combo_t = 1.5
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
			target.take_damage(xbow_dmg, global_position)
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
		hit_pos = camera.global_position + camera.global_transform.basis * Vector3(0, 0, -xbow_range)
	spawn_bolt(hit_pos, hit_target, attach_point, local_hit)
	if did_hit:
		spawn_impact(hit_pos)

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
