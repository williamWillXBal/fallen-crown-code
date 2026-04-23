# ============================================
# ENEMY.GD — Guerrier voxel avec IA, combat mêlée et ragdoll physique à la mort
# ============================================
# FONCTIONS (cherche par Ctrl+F sur le nom) :
#   _ready()                              → Init au lancement (build mesh + audio)
#   _cube(parent, pos, size, mat)         → Helper : crée un cube mesh
#   _mat(color, roughness, metallic)      → Helper : material standard
#   _mat_rim(color, r, m, rim_strength)   → Helper : material avec rim light (visible dans noir)
#   build_mesh()                          → Construit le corps voxel (25 cubes)
#   COL_BELT()                            → Couleur ceinture
#   COL_METAL_VAL()                       → Couleur métal standard
#   _play_oneshot(stream, vol)            → Helper : son non-3D one-shot dans main
#   _play_oneshot_3d(stream, vol, pos, u) → Helper : son 3D one-shot dans main
#   _physics_process(delta)               → Boucle IA (poursuite joueur + attaque)
#   take_damage(amount, from)             → Recevoir un coup, knockback, flash, sang
#   spawn_blood(kb_dir, intensity)        → Gerbe de sang voxel à l'impact
#   flash_white()                         → Flash blanc 0.1s sur tous les meshes
#   die(shot_from)                        → Mort : spawn ragdoll physique + free l'ennemi
#   spawn_blood_pool(fall_offset)         → Flaque de sang persistante au sol
#   _spawn_kill_sparkle(impact_pos)       → Pop de 7 étincelles dorées au kill (0.3s)
#   _spawn_soul_ghost(origin)             → Fantôme humanoïde 2 phases + TRAÎNÉE
#                                           lumineuse + BURST final (14 étincelles)
#   _spawn_loot_drop(origin)              → Drop 3-5 cubes ressources (fer/bois/or
#                                           /pierre) en arc balistique + rotation sol
#   _spawn_physical_ragdoll(pos, basis,   → Crée le ragdoll 9 corps articulés :
#                          kb_world, f)     head, torso_top, pelvis, 2× upper/lower_arm,
#                                           2× thigh/calf reliés par 8 PinJoint3D
#   _make_rb(parent, pos, basis, offset,  → Helper : crée un RigidBody3D avec sa collision
#            mass, col_size, col_off,       (simplifie la création des 9 corps)
#            lin_damp, ang_damp)
#   _make_joint(parent, pos, basis,       → Helper : crée un PinJoint3D entre 2 RB
#               local_pos, node_a, node_b)

# RAGDOLL PHYSIQUE — 9 CORPS ARTICULÉS :
#   - head, torso_top, pelvis, upper_arm_L/R, lower_arm_L/R, thigh_L/R, calf_L/R
#   - 8 PinJoint3D : cou, taille, épaules×2, coudes×2, hanches×2, genoux×2
#   - Impulsions "fauchage" : jambes vers -kb_world (avant, côté shooter),
#     torse vers +kb_world (arrière) → effet tapis tiré sous les pieds
#   - Sleep naturel Godot (can_sleep=true) → économie CPU auto quand repos
#
# CONSTANTES / REFS IMPORTANTES :
#   hp (30) / max_hp (30)                 → Points de vie
#   spd (3.0) / dmg (8)                   → Vitesse et dégâts
#   dying                                 → Bool : est en train de mourir ?
#   body_root                             → Node3D parent des meshes de l'ennemi vivant, offset y=+0.225
#   mesh_parts[], eye_parts[]             → Refs pour flash blanc et extinction yeux
#   head_part, arm_l/r_part, leg_l/r_part → Refs membres (utiles pour take_damage visuels)
#                                         → head_part est un Node3D conteneur (tête+casque+yeux)
#   boot_l/r_part                         → Refs bottes
#   bolts[]                               → Flèches plantées (rempli par player.gd, transférées au ragdoll)
#   death_sfx                             → AudioStreamPlayer son de mort
# ============================================

extends CharacterBody3D
var hp := 30
var max_hp := 30
var spd := 3.0
var dmg := 8
var atk_cd := 0.0
var target: Node3D
var dying := false
# Mesh refs for flash
var mesh_parts := []
var eye_parts := []
var death_sfx: AudioStreamPlayer
var hit_sfx: AudioStreamPlayer3D  # son d'impact flèche sur le corps (spatialisé)
var body_root: Node3D
# Refs membres individuels pour ragdoll simplifié (inertie indépendante, bottes qui glissent)
var head_part: Node3D
var arm_l_part: Node3D
var arm_r_part: Node3D
var leg_l_part: MeshInstance3D
var leg_r_part: MeshInstance3D
var boot_l_part: MeshInstance3D
var boot_r_part: MeshInstance3D
# Flèches plantées dans le corps (remplies par player.gd dans spawn_bolt).
# À la mort, elles sont transférées au torse_rb du ragdoll pour ne pas disparaître.
var bolts: Array[Node3D] = []
# Référence au RigidBody3D du torse du ragdoll (null tant que l'ennemi est vivant).
# Set par _spawn_physical_ragdoll au moment de la mort. Accessible via get_ragdoll_torso()
# pour que les flèches du coup létal puissent s'attacher au ragdoll au lieu de body_root.
var ragdoll_torso: RigidBody3D = null

func _ready():
	build_mesh()
	target = get_parent().player
	death_sfx = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://sounds/enemy_death.wav"):
		death_sfx.stream = load("res://sounds/enemy_death.wav")
	death_sfx.volume_db = -8.0
	add_child(death_sfx)
	# Son d'impact spatialisé (flèche qui touche le corps = thunk métallique/chair)
	hit_sfx = AudioStreamPlayer3D.new()
	if ResourceLoader.exists("res://sounds/hit_impact.wav"):
		hit_sfx.stream = load("res://sounds/hit_impact.wav")
	hit_sfx.volume_db = -6.0
	hit_sfx.unit_size = 8.0  # portée du son (plus élevé = s'entend de plus loin)
	add_child(hit_sfx)

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

# Material with rim light (contour lumineux visible dans le noir)
func _mat_rim(c: Color, r:=0.4, m:=0.75, rim_strength:=0.6) -> StandardMaterial3D:
	var mt = StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = r
	mt.metallic = m
	mt.rim_enabled = true
	mt.rim = rim_strength
	mt.rim_tint = 0.35
	return mt

func build_mesh():
	# Root décalé vers le haut pour que les bottes sortent du sol
	body_root = Node3D.new()
	body_root.position.y = 0.225
	add_child(body_root)
	# Voxel enemy — dark warrior avec rim light pour visibilité
	var skin_mat = _mat(Color(0.42, 0.3, 0.22), 0.85)
	var armor_mat = _mat_rim(Color(0.32, 0.32, 0.36), 0.4, 0.75, 0.6)
	var armor_dark = _mat_rim(Color(0.23, 0.23, 0.26), 0.4, 0.75, 0.5)
	var cloth_mat = _mat_rim(Color(0.5, 0.18, 0.1), 0.9, 0.0, 0.4)
	var boot_mat = _mat_rim(Color(0.28, 0.2, 0.14), 0.9, 0.1, 0.3)
	# Body (torso)
	var torso = _cube(body_root, Vector3(0, 0.8, 0), Vector3(0.55, 0.7, 0.35), cloth_mat)
	mesh_parts.append(torso)
	# Armor chest plate
	var chest = _cube(body_root, Vector3(0, 0.85, 0.01), Vector3(0.58, 0.55, 0.38), armor_mat)
	mesh_parts.append(chest)
	# Belt
	_cube(body_root, Vector3(0, 0.55, 0), Vector3(0.58, 0.1, 0.38), _mat(COL_BELT()))
	# Shoulders (pauldrons)
	var sh_l = _cube(body_root, Vector3(-0.35, 1.05, 0), Vector3(0.2, 0.2, 0.4), armor_dark)
	var sh_r = _cube(body_root, Vector3(0.35, 1.05, 0), Vector3(0.2, 0.2, 0.4), armor_dark)
	mesh_parts.append(sh_l)
	mesh_parts.append(sh_r)
	# Arms : pivots à l'épaule (Y=1.0) pour que la rotation fasse vraiment "lever" le bras
	# depuis l'épaule, pas pivoter sur place au centre du mesh.
	var arm_l_pivot = Node3D.new()
	arm_l_pivot.position = Vector3(-0.4, 1.0, 0)
	body_root.add_child(arm_l_pivot)
	arm_l_part = arm_l_pivot
	var arm_r_pivot = Node3D.new()
	arm_r_pivot.position = Vector3(0.4, 1.0, 0)
	body_root.add_child(arm_r_pivot)
	arm_r_part = arm_r_pivot
	# Bras (skin) — enfants des pivots, offset vers le bas pour que l'épaule soit au sommet
	var arm_l = _cube(arm_l_pivot, Vector3(0, -0.3, 0), Vector3(0.18, 0.55, 0.22), skin_mat)
	var arm_r = _cube(arm_r_pivot, Vector3(0, -0.3, 0), Vector3(0.18, 0.55, 0.22), skin_mat)
	mesh_parts.append(arm_l)
	mesh_parts.append(arm_r)
	# Forearm armor (suit la rotation des pivots)
	_cube(arm_l_pivot, Vector3(0, -0.58, 0), Vector3(0.22, 0.22, 0.26), armor_mat)
	_cube(arm_r_pivot, Vector3(0, -0.58, 0), Vector3(0.22, 0.22, 0.26), armor_mat)
	# Hands (suivent aussi)
	_cube(arm_l_pivot, Vector3(0, -0.82, 0), Vector3(0.18, 0.15, 0.2), skin_mat)
	_cube(arm_r_pivot, Vector3(0, -0.82, 0), Vector3(0.18, 0.15, 0.2), skin_mat)
	# Legs
	var leg_l = _cube(body_root, Vector3(-0.15, 0.15, 0), Vector3(0.2, 0.5, 0.25), _mat(Color(0.22, 0.18, 0.14)))
	var leg_r = _cube(body_root, Vector3(0.15, 0.15, 0), Vector3(0.2, 0.5, 0.25), _mat(Color(0.22, 0.18, 0.14)))
	leg_l_part = leg_l
	leg_r_part = leg_r
	# Boots (Z négatif = pointées vers l'avant de l'ennemi, comme de vrais pieds)
	var boot_l = _cube(body_root, Vector3(-0.15, -0.15, -0.05), Vector3(0.22, 0.15, 0.3), boot_mat)
	var boot_r = _cube(body_root, Vector3(0.15, -0.15, -0.05), Vector3(0.22, 0.15, 0.3), boot_mat)
	boot_l_part = boot_l
	boot_r_part = boot_r
	# Head group : tête + casque + visière + yeux + crête dans un Node3D conteneur.
	# Comme ça quand on tweene la rotation pour le Niveau 3 (cou mou), tout tourne
	# ensemble et la tête ne s'enfonce plus dans le casque.
	var head_group = Node3D.new()
	head_group.position = Vector3(0, 1.45, 0)
	body_root.add_child(head_group)
	head_part = head_group
	# Head (skin)
	var head = _cube(head_group, Vector3(0, 0, 0), Vector3(0.4, 0.4, 0.4), skin_mat)
	mesh_parts.append(head)
	# Helmet
	var helmet = _cube(head_group, Vector3(0, 0.15, 0), Vector3(0.45, 0.22, 0.45), armor_mat)
	mesh_parts.append(helmet)
	# Helmet visor slit
	_cube(head_group, Vector3(0, -0.03, -0.2), Vector3(0.3, 0.04, 0.02), _mat(Color(0.05, 0.05, 0.05)))
	# Eyes (red emissive through visor)
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.9, 0.1, 0.05)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.9, 0.1, 0.03)
	eye_mat.emission_energy_multiplier = 3.0
	var eye_l = _cube(head_group, Vector3(-0.1, -0.03, -0.21), Vector3(0.07, 0.04, 0.02), eye_mat)
	var eye_r = _cube(head_group, Vector3(0.1, -0.03, -0.21), Vector3(0.07, 0.04, 0.02), eye_mat)
	mesh_parts.append(eye_l)
	mesh_parts.append(eye_r)
	eye_parts.append(eye_l)
	eye_parts.append(eye_r)
	# Helmet crest (little blocky ridge on top)
	_cube(head_group, Vector3(0, 0.33, 0), Vector3(0.08, 0.1, 0.3), cloth_mat)
	# Weapon — axe in right hand
	var weapon = Node3D.new()
	weapon.position = Vector3(0.45, 0.3, -0.15)
	# Axe handle
	_cube(weapon, Vector3.ZERO, Vector3(0.08, 0.8, 0.08), _mat(Color(0.35, 0.22, 0.12)))
	# Axe head (with rim for visibility)
	_cube(weapon, Vector3(0.18, 0.3, 0), Vector3(0.3, 0.25, 0.05), _mat_rim(COL_METAL_VAL(), 0.3, 0.85, 0.5))
	_cube(weapon, Vector3(-0.12, 0.3, 0), Vector3(0.15, 0.15, 0.05), _mat_rim(COL_METAL_VAL(), 0.3, 0.85, 0.5))
	body_root.add_child(weapon)

func COL_BELT() -> Color:
	return Color(0.2, 0.14, 0.1)

func COL_METAL_VAL() -> Color:
	return Color(0.55, 0.55, 0.6)

# Joue un son one-shot NON-3D dans main (survit au queue_free de self).
# Utilisé pour death_sfx : le son doit continuer alors que l'enemy est détruit.
func _play_oneshot(stream: AudioStream, volume: float):
	if not stream:
		return
	var main = get_parent()
	if not is_instance_valid(main):
		return
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume
	main.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# Joue un son one-shot 3D à une position dans main (survit au queue_free de self).
# Utilisé pour hit_sfx sur le coup létal : son coupé sinon car enemy freed juste après.
func _play_oneshot_3d(stream: AudioStream, volume: float, pos: Vector3, unit_size: float = 8.0):
	if not stream:
		return
	var main = get_parent()
	if not is_instance_valid(main):
		return
	var p = AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume
	p.unit_size = unit_size
	main.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

func _physics_process(delta):
	if dying: return
	if not is_instance_valid(target): return
	var dir = (target.global_position - global_position)
	dir.y = 0; var dist = dir.length()
	if dist > 2.0:
		dir = dir.normalized()
		velocity.x = dir.x * spd; velocity.z = dir.z * spd
		look_at(target.global_position); rotation.x = 0
	else:
		velocity.x = 0; velocity.z = 0
		if atk_cd <= 0: atk_cd = 1.0; target.take_damage(dmg)
	if not is_on_floor(): velocity.y -= 15 * delta
	move_and_slide()
	if atk_cd > 0: atk_cd -= delta

func take_damage(amount: int, from: Vector3):
	if dying: return
	hp -= amount
	# Son d'impact spatialisé (thunk de la flèche qui touche le corps).
	# One-shot dans main → survit au queue_free de l'enemy si c'est un coup létal.
	if hit_sfx and hit_sfx.stream:
		_play_oneshot_3d(hit_sfx.stream, -6.0, global_position, 8.0)
	get_parent().get_node("HUD").hit_timer = 0.15
	var kb = (global_position - from).normalized(); kb.y = 0
	# Knockback dirigé renforcé, proportionnel aux dégâts (5 dmg → 0.45m, 25 dmg → 1.05m, cap 1.2m)
	var kb_strength = clamp(0.3 + amount * 0.03, 0.3, 1.2)
	# Bonus au kill : +50% pour un effet d'éjection plus brutal
	if hp <= 0:
		kb_strength *= 1.5
	global_position += kb * kb_strength
	# Giclée de sang au point d'impact, dirigée dans le sens du knockback
	spawn_blood(kb, 1.0)
	flash_white()
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.88, 0.05)
	tw.tween_property(self, "scale", Vector3.ONE, 0.1)
	if hp <= 0:
		# Double giclée au kill : gore massif visible au ralenti (32 particules au total)
		spawn_blood(kb, 2.0)
		spawn_blood(kb, 2.0)
		die(from)

# Spawn de cubes voxel rouge sang en arc balistique (montée + chute)
# kb_dir : direction du knockback (utilisée pour la dispersion conique)
# intensity : 1.0 pour un hit normal, 2.0 pour un kill (doublée pour gore massif)
func spawn_blood(kb_dir: Vector3, intensity: float):
	var main = get_parent()
	var count = int(10 * intensity)
	for i in range(count):
		var p = MeshInstance3D.new()
		var pm = BoxMesh.new()
		# Tailles plus variées : petits éclats et gros morceaux (0.06 à 0.16)
		var sz = 0.06 + randf() * 0.10
		pm.size = Vector3(sz, sz, sz)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.08, 0.05)  # COL_BLOOD
		mat.roughness = 0.7
		# Léger émissif pour que le sang soit visible dans l'ambiance sombre
		mat.emission_enabled = true
		mat.emission = Color(0.25, 0.05, 0.03)
		mat.emission_energy_multiplier = 0.3
		pm.material = mat
		p.mesh = pm
		main.add_child(p)
		# Point d'impact : hauteur torse
		p.global_position = global_position + Vector3(0, 0.9, 0)
		p.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		# Dispersion conique plus large et plus haute (impact violent)
		var spread = Vector3(
			kb_dir.x * (2.2 + randf() * 1.5) + randf_range(-0.8, 0.8),
			randf_range(1.8, 3.2),
			kb_dir.z * (2.2 + randf() * 1.5) + randf_range(-0.8, 0.8)
		)
		# Arc balistique en 2 phases : montée ease_out, chute ease_in (gravité simulée)
		var dur = randf_range(0.7, 1.2)
		var apex = p.global_position + spread * (dur * 0.4)
		apex.y += 0.8
		var landing = p.global_position + spread * dur
		landing.y = global_position.y + 0.02
		# Le tween doit être attaché à la particule elle-même (pas à self), sinon
		# si l'ennemi est free() avant la fin de l'animation (cas du kill qui appelle die()),
		# les particules restent figées en l'air. Avec p.create_tween() le tween vit
		# avec la particule, même si l'ennemi disparaît.
		var tw = p.create_tween()
		tw.tween_property(p, "global_position", apex, dur * 0.4).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "global_position", landing, dur * 0.6).set_ease(Tween.EASE_IN)
		tw.tween_callback(p.queue_free)

# Appelée par player.gd quand une flèche se plante dans cet ennemi.
# L'ennemi garde la liste pour transférer les flèches au ragdoll à la mort
# (sinon elles disparaissent avec le body_root qui est free()).
func register_bolt(bolt: Node3D):
	bolts.append(bolt)

# Appelée par player.gd AVANT take_damage pour obtenir le noeud d'attache des flèches.
# Retourne body_root qui est le parent des meshes visuels — la flèche plantée y sera
# enfant direct et suivra tout mouvement de l'ennemi (y compris le knockback).
func get_bolt_attach() -> Node3D:
	return body_root

# Appelée par player.gd APRÈS take_damage pour détecter si l'ennemi est mort.
# Si non null, le coup létal vient de créer le ragdoll → la flèche doit s'attacher
# au torso_rb (qui survit dans la scène) au lieu de body_root (qui va être free).
func get_ragdoll_torso() -> RigidBody3D:
	return ragdoll_torso

func flash_white():
	var white = StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1)
	white.emission_enabled = true
	white.emission = Color(1, 1, 1)
	white.emission_energy_multiplier = 2.5
	for p in mesh_parts:
		if is_instance_valid(p):
			p.material_override = white
	var tw = create_tween()
	tw.tween_callback(func():
		if is_instance_valid(self):
			for p in mesh_parts:
				if is_instance_valid(p):
					p.material_override = null
	).set_delay(0.1)

func die(shot_from: Vector3 = Vector3.ZERO):
	dying = true
	get_parent().player.kills += 1
	get_parent().enemies.erase(self)
	set_physics_process(false)
	velocity = Vector3.ZERO
	# Son de mort : volume adapté à la distance au joueur (4 zones)
	# ─────────────────────────────────────────────────────────────────────
	# 2 CONFIGS POSSIBLES (à tester en conditions réelles, switcher si besoin)
	#
	# CONFIG A (active) — seuils LARGES adaptés au BR PvP (combats 15-25m) :
	#   <10m=-14dB / 10-25m=-17dB / 25-45m=-20dB / >45m=silence
	#
	# CONFIG B (commentée) — seuils SERRÉS (version précédente) :
	#   <5m=-16dB / 5-15m=-19dB / 15-30m=-22dB / >30m=silence
	# ─────────────────────────────────────────────────────────────────────
	if death_sfx and death_sfx.stream:
		var player_ref_for_dist = get_parent().player
		var dist_to_player = 20.0  # Fallback si player non trouvé
		if is_instance_valid(player_ref_for_dist):
			dist_to_player = global_position.distance_to(player_ref_for_dist.global_position)
		# --- CONFIG A (ACTIVE) ---
		if dist_to_player < 45.0:
			var death_vol: float
			if dist_to_player < 10.0:
				death_vol = -14.0
			elif dist_to_player < 25.0:
				death_vol = -17.0
			else:
				death_vol = -20.0
			_play_oneshot(death_sfx.stream, death_vol)
		# --- CONFIG B (INACTIVE, décommenter + commenter CONFIG A pour switcher) ---
		#if dist_to_player < 30.0:
		#	var death_vol: float
		#	if dist_to_player < 5.0:
		#		death_vol = -16.0
		#	elif dist_to_player < 15.0:
		#		death_vol = -19.0
		#	else:
		#		death_vol = -22.0
		#	_play_oneshot(death_sfx.stream, death_vol)
	# Ralenti cinématique 0.3s au kill
	Engine.time_scale = 0.3
	var slow_timer = get_tree().create_timer(0.3, true, false, true)
	slow_timer.timeout.connect(func(): Engine.time_scale = 1.0)
	# Direction du knockback en coords WORLD (pour l'impulsion du ragdoll)
	var kb_dir_world = Vector3.ZERO
	if shot_from != Vector3.ZERO:
		kb_dir_world = (global_position - shot_from).normalized()
		kb_dir_world.y = 0
		if kb_dir_world.length() > 0.01:
			kb_dir_world = kb_dir_world.normalized()
	# Impact_force : courbe en cloche selon distance de tir
	var shot_dist = global_position.distance_to(shot_from) if shot_from != Vector3.ZERO else 12.0
	var impact_force: float
	if shot_dist < 12.0:
		impact_force = lerp(0.5, 1.0, shot_dist / 12.0)
	else:
		impact_force = lerp(1.0, 0.3, clamp((shot_dist - 12.0) / 28.0, 0.0, 1.0))
	# Capture la pose de l'ennemi avant de free le corps
	var death_pos = global_position
	var death_basis = global_transform.basis
	# Secousse caméra selon distance : proche = 0.10m, moyen = 0.05m, loin = 0.02m
	var player_ref = get_parent().player
	if player_ref != null and is_instance_valid(player_ref) and player_ref.has_method("camera_shake"):
		var shake_amp := 0.10 if shot_dist < 5.0 else (0.05 if shot_dist < 15.0 else 0.02)
		player_ref.camera_shake(shake_amp, 0.25)
	# Flaque de sang persistante sous l'ennemi
	spawn_blood_pool(Vector3.ZERO)
	# Spawn le ragdoll physique (RigidBody3D + PinJoint3D, vraie physique)
	_spawn_physical_ragdoll(death_pos, death_basis, kb_dir_world, impact_force)
	# Feedback de kill non-invasif (remplace l'ancien effet âme trop lourd) :
	# - Pop d'étincelles dorées à la poitrine (0.3s, court et lisible)
	# - Fantôme blanc qui monte rapidement du corps (1.5s, transparent)
	# - Drop de 3-5 cubes de ressources (fer/bois/or/pierre) en arc balistique
	var impact_pos = death_pos + Vector3(0, 1.0, 0)  # Poitrine
	_spawn_kill_sparkle(impact_pos)
	_spawn_soul_ghost(impact_pos)
	_spawn_loot_drop(impact_pos)
	# Le corps original est remplacé par les RigidBody3D → on le libère
	queue_free()

# Flaque de sang persistante au sol sous le cadavre (marque d'impact)
# 6 cubes voxel rouge sombre aplatis, disposés en tache irrégulière sous le torse
func spawn_blood_pool(fall_offset: Vector3):
	var main = get_parent()
	# fall_offset est en coords locales de self (orienté via look_at), on le transforme en monde
	var world_offset = global_transform.basis * fall_offset
	# Le torse couché est à l'extrémité de body_offset, on centre la flaque dessous
	var center = global_position + world_offset
	center.y = 0.03  # Collé au sol
	for i in range(6):
		var p = MeshInstance3D.new()
		var pm = BoxMesh.new()
		var sz_x = randf_range(0.3, 0.55)
		var sz_z = randf_range(0.3, 0.55)
		pm.size = Vector3(sz_x, 0.03, sz_z)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.05, 0.03)
		mat.roughness = 0.4
		mat.emission_enabled = true
		mat.emission = Color(0.25, 0.04, 0.02)
		mat.emission_energy_multiplier = 0.5
		pm.material = mat
		p.mesh = pm
		main.add_child(p)
		# Dispersion autour du centre pour tache irrégulière
		p.global_position = center + Vector3(
			randf_range(-0.5, 0.5),
			0,
			randf_range(-0.5, 0.5)
		)

# Pop d'étincelles dorées au point d'impact du coup létal.
# 7 petits cubes voxel dorés émissifs jaillissent en sphère avec biais vers le haut,
# puis fade alpha + scale shrink en 0.3s. Effet court, non-invasif, marque le kill.
func _spawn_kill_sparkle(impact_pos: Vector3):
	var main = get_parent()
	if not is_instance_valid(main):
		return
	for i_sp in range(7):
		var s = MeshInstance3D.new()
		var sm = BoxMesh.new()
		var sz = randf_range(0.06, 0.10)
		sm.size = Vector3(sz, sz, sz)
		var smat = StandardMaterial3D.new()
		smat.albedo_color = Color(1.0, 0.85, 0.30, 1.0)
		smat.emission_enabled = true
		smat.emission = Color(1.0, 0.78, 0.20)
		smat.emission_energy_multiplier = 3.0
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.material = smat
		s.mesh = sm
		main.add_child(s)
		s.global_position = impact_pos
		s.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		# Direction aléatoire en sphère unité, biais vers le haut
		var dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.3, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		var dist = randf_range(0.5, 1.0)
		var end_pos = impact_pos + dir * dist
		var dur = 0.3
		var tw = s.create_tween()
		tw.set_parallel(true)
		tw.tween_property(s, "global_position", end_pos, dur).set_ease(Tween.EASE_OUT)
		tw.tween_property(smat, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
		tw.tween_property(s, "scale", Vector3.ZERO, dur).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(s.queue_free)

# Fantôme qui sort du corps : silhouette humanoïde + TRAÎNÉE + BURST final.
# Version pour PvP (total 1.5s), alpha 0.15 (très transparent).
# 6 cubes blancs (tête, torse, 2 bras, 2 jambes) avec material partagé.
# - PHASE 1 (0-0.8s) : pieds au sol, montée fluide 1.8m, scale grow 1.0→1.1.
# - PHASE 2 (0.8-1.1s) : BOOST accéléré +3m + étirement 1.4 + fade alpha
#   + TRAÎNÉE LUMINEUSE (10 petites particules blanches qui apparaissent
#   derrière le fantôme et fadent sur 0.35s).
# - BURST FINAL (à 1.1s) : 14 étincelles blanches en sphère au sommet
#   → explosion finale marquante au moment où le fantôme disparaît.
func _spawn_soul_ghost(origin: Vector3):
	var main = get_parent()
	if not is_instance_valid(main):
		return
	var ghost = Node3D.new()
	main.add_child(ghost)
	# Pieds du fantôme au sol (origin est à 1m = poitrine → on descend de 1m)
	ghost.global_position = origin - Vector3(0, 1.0, 0)
	# Material blanc émissif TRÈS TRANSPARENT PARTAGÉ entre les 6 cubes
	var ghost_mat = StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.15)
	ghost_mat.emission_enabled = true
	ghost_mat.emission = Color(1.0, 1.0, 1.0)
	ghost_mat.emission_energy_multiplier = 1.4
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Helper local pour créer un cube du fantôme
	var add_ghost_cube = func(local_pos: Vector3, size: Vector3):
		var m = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = size
		bm.material = ghost_mat
		m.mesh = bm
		ghost.add_child(m)
		m.position = local_pos
	# Silhouette humanoïde (6 cubes, proportions ~ennemi vivant ~1.85m)
	add_ghost_cube.call(Vector3(0, 1.65, 0), Vector3(0.32, 0.32, 0.32))    # Tête
	add_ghost_cube.call(Vector3(0, 1.10, 0), Vector3(0.45, 0.55, 0.25))    # Torse
	add_ghost_cube.call(Vector3(-0.35, 1.00, 0), Vector3(0.15, 0.55, 0.15))  # Bras G
	add_ghost_cube.call(Vector3(0.35, 1.00, 0), Vector3(0.15, 0.55, 0.15))   # Bras D
	add_ghost_cube.call(Vector3(-0.12, 0.40, 0), Vector3(0.18, 0.70, 0.18))  # Jambe G
	add_ghost_cube.call(Vector3(0.12, 0.40, 0), Vector3(0.18, 0.70, 0.18))   # Jambe D
	# Paramètres d'animation 2 phases
	var rise_height = 1.8
	var ghost_dur = 0.8         # Phase 1 : montée normale
	var boost_height = 3.0      # Phase 2 : boost final (+3m)
	var boost_dur = 0.3         # Phase 2 : durée accélérée
	var start_y = ghost.global_position.y
	# PHASE 1 : montée fluide + léger grow (PAS de fade, reste visible)
	var tw1 = ghost.create_tween()
	tw1.set_parallel(true)
	tw1.tween_property(ghost, "global_position:y", start_y + rise_height, ghost_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw1.tween_property(ghost, "scale", Vector3.ONE * 1.1, ghost_dur).set_ease(Tween.EASE_OUT)
	# PHASE 2 : boost accéléré + trainée lumineuse + burst final (via timer)
	main.get_tree().create_timer(ghost_dur).timeout.connect(func():
		if not is_instance_valid(ghost):
			return
		# --- Boost accéléré + fade + étirement ---
		var tw2 = ghost.create_tween()
		tw2.set_parallel(true)
		tw2.tween_property(ghost, "global_position:y", start_y + rise_height + boost_height, boost_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw2.tween_property(ghost_mat, "albedo_color:a", 0.0, boost_dur).set_ease(Tween.EASE_IN)
		tw2.tween_property(ghost, "scale", Vector3.ONE * 1.4, boost_dur).set_ease(Tween.EASE_OUT)
		# --- TRAÎNÉE : 10 particules blanches échelonnées sur la durée du boost ---
		# Apparaissent à la position courante du fantôme, fade rapide en place
		for t_idx in range(10):
			var trail_delay = float(t_idx) * 0.028
			main.get_tree().create_timer(trail_delay).timeout.connect(func():
				if not is_instance_valid(ghost):
					return
				var trail = MeshInstance3D.new()
				var tm = BoxMesh.new()
				var tsz = randf_range(0.08, 0.14)
				tm.size = Vector3(tsz, tsz, tsz)
				var tmat = StandardMaterial3D.new()
				tmat.albedo_color = Color(1.0, 1.0, 1.0, 0.80)
				tmat.emission_enabled = true
				tmat.emission = Color(1.0, 1.0, 1.0)
				tmat.emission_energy_multiplier = 2.2
				tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				tm.material = tmat
				trail.mesh = tm
				main.add_child(trail)
				# Position à peu près au centre du fantôme (milieu du torse)
				trail.global_position = ghost.global_position + Vector3(
					randf_range(-0.18, 0.18),
					1.0 + randf_range(-0.35, 0.35),
					randf_range(-0.18, 0.18)
				)
				trail.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
				var tw_trail = trail.create_tween()
				tw_trail.set_parallel(true)
				tw_trail.tween_property(tmat, "albedo_color:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
				tw_trail.tween_property(trail, "scale", Vector3.ZERO, 0.35).set_ease(Tween.EASE_IN)
				tw_trail.chain().tween_callback(trail.queue_free)
			)
		# --- BURST FINAL au sommet : 14 étincelles blanches en sphère ---
		tw2.chain().tween_callback(func():
			if not is_instance_valid(main):
				return
			# Position finale : centre du fantôme au sommet
			var burst_origin = origin + Vector3(0, rise_height + boost_height, 0)
			if is_instance_valid(ghost):
				burst_origin = ghost.global_position + Vector3(0, 1.0, 0)
				ghost.queue_free()
			for b_idx in range(14):
				var b = MeshInstance3D.new()
				var bm = BoxMesh.new()
				var bsz = randf_range(0.07, 0.12)
				bm.size = Vector3(bsz, bsz, bsz)
				var bmat = StandardMaterial3D.new()
				bmat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
				bmat.emission_enabled = true
				bmat.emission = Color(1.0, 1.0, 1.0)
				bmat.emission_energy_multiplier = 3.5
				bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				bm.material = bmat
				b.mesh = bm
				main.add_child(b)
				b.global_position = burst_origin
				b.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
				# Direction sphère aléatoire (tous sens pour effet "explosion")
				var dir = Vector3(
					randf_range(-1.0, 1.0),
					randf_range(-1.0, 1.0),
					randf_range(-1.0, 1.0)
				).normalized()
				var dist = randf_range(0.7, 1.3)
				var end_pos = burst_origin + dir * dist
				var burst_dur = 0.4
				var tw_b = b.create_tween()
				tw_b.set_parallel(true)
				tw_b.tween_property(b, "global_position", end_pos, burst_dur).set_ease(Tween.EASE_OUT)
				tw_b.tween_property(bmat, "albedo_color:a", 0.0, burst_dur).set_ease(Tween.EASE_IN)
				tw_b.tween_property(b, "scale", Vector3.ZERO, burst_dur).set_ease(Tween.EASE_IN)
				tw_b.chain().tween_callback(b.queue_free)
		)
	)

# Loot drop : 3-5 cubes de ressources qui jaillissent du cadavre en arc balistique.
# Types pondérés : fer 50%, bois 25%, or 15%, pierre 10% (thème guerrier médiéval).
# Arc : montée 0.32s (ease out) + descente 0.48s (ease in), atterrissage à 0.8-1.8m.
# Au sol : rotation Y continue (3s/tour) → signal visuel "ramassable".
# Cubes persistants (pas de queue_free auto, le pickup viendra plus tard).
func _spawn_loot_drop(origin: Vector3):
	var main = get_parent()
	if not is_instance_valid(main):
		return
	# Table de loot pondérée (chaque type a un nom pour le pickup)
	var loot_types = [
		{"name": "fer",    "albedo": Color(0.78, 0.78, 0.82), "emission": Color(0.5, 0.5, 0.55), "weight": 50},
		{"name": "bois",   "albedo": Color(0.55, 0.35, 0.15), "emission": Color(0.3, 0.18, 0.08), "weight": 25},
		{"name": "or",     "albedo": Color(1.0, 0.82, 0.25),  "emission": Color(0.8, 0.60, 0.10), "weight": 15},
		{"name": "pierre", "albedo": Color(0.55, 0.55, 0.58), "emission": Color(0.3, 0.30, 0.32), "weight": 10},
	]
	var total_weight = 0
	for lt in loot_types:
		total_weight += lt.weight
	# Niveau du sol sous le cadavre (origin est à +1m = poitrine)
	var floor_y = origin.y - 1.0 + 0.11  # +0.11 = moitié hauteur cube
	var nb_drops = randi_range(3, 5)
	for i_loot in range(nb_drops):
		# Pick pondéré
		var r = randi_range(1, total_weight)
		var acc = 0
		var picked = loot_types[0]
		for lt in loot_types:
			acc += lt.weight
			if r <= acc:
				picked = lt
				break
		# Création cube voxel
		var cube = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3(0.22, 0.22, 0.22)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = picked.albedo
		mat.roughness = 0.7
		mat.emission_enabled = true
		mat.emission = picked.emission
		mat.emission_energy_multiplier = 0.6
		bm.material = mat
		cube.mesh = bm
		main.add_child(cube)
		# Meta pour le pickup : type de ressource + flag "not picked yet"
		cube.set_meta("loot_type", picked.name)
		cube.set_meta("picked", false)
		cube.add_to_group("loot")
		# Position initiale : légèrement autour de la poitrine
		cube.global_position = origin + Vector3(
			randf_range(-0.15, 0.15),
			randf_range(-0.1, 0.1),
			randf_range(-0.15, 0.15)
		)
		cube.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		# Arc balistique : direction aléatoire, distance 0.8-1.8m au sol
		var drop_angle = randf() * TAU
		var drop_dist = randf_range(0.8, 1.8)
		var land_pos = Vector3(
			origin.x + cos(drop_angle) * drop_dist,
			floor_y,
			origin.z + sin(drop_angle) * drop_dist
		)
		# Peak de l'arc (mi-chemin, + hauteur supplémentaire)
		var peak_pos = (cube.global_position + land_pos) * 0.5
		peak_pos.y = max(cube.global_position.y, land_pos.y) + randf_range(0.5, 1.0)
		# Tween 2 phases : montée + descente
		var up_dur = 0.32
		var down_dur = 0.48
		var tw = cube.create_tween()
		tw.tween_property(cube, "global_position", peak_pos, up_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(cube, "global_position", land_pos, down_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# Au sol : démarrer rotation Y continue (signal "ramassable")
		var start_rot_y = cube.rotation.y
		tw.tween_callback(func():
			if not is_instance_valid(cube):
				return
			var spin_tw = cube.create_tween()
			spin_tw.set_loops()
			spin_tw.tween_property(cube, "rotation:y", start_rot_y + TAU, 3.0).from(start_rot_y)
		)

# Spawn du ragdoll physique complet : 3 RigidBody3D (torse + 2 bras) reliés par PinJoint3D.
# Le torse contient aussi tête, casque, jambes, bottes (étape 1 simplifiée).
# Étape 2 prévue : détacher la tête et les jambes avec leurs propres joints.
func _spawn_physical_ragdoll(pos: Vector3, body_basis: Basis, kb_world: Vector3, force: float):
	# ============================================================
	# RAGDOLL 9 CORPS ARTICULÉ (tête, torso_top, pelvis, 2×upper_arm,
	# 2×lower_arm, 2×thigh, 2×calf) reliés par 8 PinJoint3D.
	# Coordonnées Y world de chaque pivot (référence = pos.y au sol) :
	#   head       : Y = +1.675 (base du cou)
	#   torso_top  : Y = +1.225 (épaule, centre haut du tronc)
	#   pelvis     : Y = +0.775 (taille, haut du bassin)
	#   upper_arm  : Y = +1.225 (épaule)
	#   lower_arm  : Y = +0.825 (coude)
	#   thigh      : Y = +0.775 (hanche)
	#   calf       : Y = +0.325 (genou)
	# ============================================================
	var main = get_parent()
	# Matériaux (recréés car l'ennemi va être free)
	var skin = _mat(Color(0.78, 0.62, 0.45), 0.85, 0.0)
	var armor = _mat_rim(Color(0.32, 0.32, 0.35), 0.35, 0.8, 0.6)
	var armor_dark = _mat_rim(Color(0.23, 0.23, 0.26), 0.4, 0.75, 0.5)
	var cloth = _mat_rim(Color(0.5, 0.18, 0.1), 0.9, 0.0, 0.4)
	var boot_mat = _mat_rim(Color(0.28, 0.2, 0.14), 0.9, 0.1, 0.3)
	var leg_mat = _mat(Color(0.22, 0.18, 0.14))
	var eye_off = StandardMaterial3D.new()
	eye_off.albedo_color = Color(0.08, 0.03, 0.03)
	var visor_mat = _mat(Color(0.05, 0.05, 0.05))

	# === TORSO_TOP : torse supérieur (épaules à taille), pivot à Y=1.225 ===
	# Collision taille INTERMÉDIAIRE : pas trop grosse (évite coincement) mais pas
	# trop petite (sinon corps trop mou). Damping modéré pour style GTA.
	var torso_top = _make_rb(main, pos, body_basis, Vector3(0, 1.225, 0), 4.0, Vector3(0.52, 0.48, 0.35), Vector3(0, -0.12, 0), 0.3, 1.5)
	ragdoll_torso = torso_top  # ref pour player.gd (flèches du coup létal)
	_cube(torso_top, Vector3(0, -0.19, 0), Vector3(0.55, 0.58, 0.35), cloth)        # chemise (étirée)
	_cube(torso_top, Vector3(0, -0.15, 0.01), Vector3(0.58, 0.5, 0.38), armor)      # chest plate
	_cube(torso_top, Vector3(-0.38, 0.0, 0), Vector3(0.28, 0.3, 0.42), armor_dark)  # pauldron L (plus gros, descend plus bas)
	_cube(torso_top, Vector3(0.38, 0.0, 0), Vector3(0.28, 0.3, 0.42), armor_dark)   # pauldron R

	# === PELVIS : bassin (taille à hanches), pivot à Y=0.775 ===
	var pelvis = _make_rb(main, pos, body_basis, Vector3(0, 0.775, 0), 3.0, Vector3(0.48, 0.4, 0.35), Vector3(0, 0, 0), 0.3, 1.5)
	# Tirs de loin : bassin plus rigide pour qu'il ne se ballotte pas et reste
	# solidaire du torse (sinon effet "baggy" peu réaliste sur impacts faibles).
	if force < 0.5:
		pelvis.linear_damp = 1.2
		pelvis.angular_damp = 4.0
	_cube(pelvis, Vector3(0, 0, 0), Vector3(0.55, 0.45, 0.4), cloth)               # bassin étiré
	_cube(pelvis, Vector3(0, 0.15, 0), Vector3(0.58, 0.15, 0.4), _mat(COL_BELT())) # ceinture

	# === HEAD : tête + casque + visière + yeux + crête, pivot au cou Y=1.675 ===
	var head = _make_rb(main, pos, body_basis, Vector3(0, 1.675, 0), 1.5, Vector3(0.4, 0.5, 0.4), Vector3(0, 0.15, 0), 0.25, 1.0)
	_cube(head, Vector3(0, 0.1, 0), Vector3(0.42, 0.5, 0.42), skin)             # tête (descend plus bas pour couvrir cou)
	_cube(head, Vector3(0, 0.3, 0), Vector3(0.47, 0.24, 0.47), armor)           # casque
	_cube(head, Vector3(0, 0.12, -0.2), Vector3(0.3, 0.04, 0.02), visor_mat)    # visière
	_cube(head, Vector3(-0.1, 0.12, -0.21), Vector3(0.07, 0.04, 0.02), eye_off) # œil L
	_cube(head, Vector3(0.1, 0.12, -0.21), Vector3(0.07, 0.04, 0.02), eye_off)  # œil R
	_cube(head, Vector3(0, 0.48, 0), Vector3(0.08, 0.1, 0.3), cloth)            # crête

	# === BRAS (4 segments : 2 upper + 2 lower) ===
	var upper_l = _make_rb(main, pos, body_basis, Vector3(-0.4, 1.225, 0), 0.6, Vector3(0.2, 0.45, 0.2), Vector3(0, -0.2, 0), 0.2, 0.8)
	_cube(upper_l, Vector3(0, -0.18, 0), Vector3(0.22, 0.5, 0.24), skin)  # déborde vers +0.07 et -0.43
	var upper_r = _make_rb(main, pos, body_basis, Vector3(0.4, 1.225, 0), 0.6, Vector3(0.2, 0.45, 0.2), Vector3(0, -0.2, 0), 0.2, 0.8)
	_cube(upper_r, Vector3(0, -0.18, 0), Vector3(0.22, 0.5, 0.24), skin)
	var lower_l = _make_rb(main, pos, body_basis, Vector3(-0.4, 0.825, 0), 0.5, Vector3(0.2, 0.45, 0.24), Vector3(0, -0.2, 0), 0.2, 0.8)
	_cube(lower_l, Vector3(0, -0.1, 0), Vector3(0.24, 0.4, 0.28), armor)   # avant-bras (déborde vers +0.1)
	_cube(lower_l, Vector3(0, -0.35, 0), Vector3(0.2, 0.14, 0.22), skin)   # main
	var lower_r = _make_rb(main, pos, body_basis, Vector3(0.4, 0.825, 0), 0.8, Vector3(0.2, 0.45, 0.24), Vector3(0, -0.2, 0), 0.2, 0.8)
	_cube(lower_r, Vector3(0, -0.1, 0), Vector3(0.24, 0.4, 0.28), armor)
	_cube(lower_r, Vector3(0, -0.35, 0), Vector3(0.2, 0.14, 0.22), skin)
	# Hache attachée au lower_r (main droite)
	_cube(lower_r, Vector3(0.05, -0.3, -0.15), Vector3(0.08, 0.8, 0.08), _mat(Color(0.35, 0.22, 0.12)))  # manche
	_cube(lower_r, Vector3(0.23, 0, -0.15), Vector3(0.3, 0.25, 0.05), _mat_rim(COL_METAL_VAL(), 0.3, 0.85, 0.5))  # lame

	# === JAMBES (4 segments : 2 thigh + 2 calf) ===
	var thigh_l = _make_rb(main, pos, body_basis, Vector3(-0.15, 0.775, 0), 1.5, Vector3(0.2, 0.48, 0.26), Vector3(0, -0.225, 0), 0.25, 1.0)
	_cube(thigh_l, Vector3(0, -0.2, 0), Vector3(0.22, 0.52, 0.28), leg_mat)  # déborde vers +0.06 et -0.46
	var thigh_r = _make_rb(main, pos, body_basis, Vector3(0.15, 0.775, 0), 1.5, Vector3(0.2, 0.48, 0.26), Vector3(0, -0.225, 0), 0.25, 1.0)
	_cube(thigh_r, Vector3(0, -0.2, 0), Vector3(0.22, 0.52, 0.28), leg_mat)
	var calf_l = _make_rb(main, pos, body_basis, Vector3(-0.15, 0.325, 0), 1.0, Vector3(0.2, 0.48, 0.28), Vector3(0, -0.2, 0), 0.25, 1.0)
	_cube(calf_l, Vector3(0, -0.1, 0), Vector3(0.22, 0.4, 0.28), leg_mat)           # mollet (déborde vers +0.1)
	_cube(calf_l, Vector3(0, -0.34, -0.05), Vector3(0.24, 0.18, 0.32), boot_mat)    # botte
	var calf_r = _make_rb(main, pos, body_basis, Vector3(0.15, 0.325, 0), 1.0, Vector3(0.2, 0.48, 0.28), Vector3(0, -0.2, 0), 0.25, 1.0)
	_cube(calf_r, Vector3(0, -0.1, 0), Vector3(0.22, 0.4, 0.28), leg_mat)
	_cube(calf_r, Vector3(0, -0.34, -0.05), Vector3(0.24, 0.18, 0.32), boot_mat)

	# === JOINTS ANATOMIQUES (Hinge + ConeTwist) ===
	# Pour chaque articulation, on utilise le type qui correspond à la biomécanique :
	# - ConeTwist pour les articulations sphériques (cou, épaules, hanches, taille)
	# - Hinge pour les articulations en charnière (coudes, genoux)
	# IMPORTANT : un cadavre n'a AUCUN tonus musculaire, ses articulations sont
	# beaucoup plus lâches qu'un corps vivant. On met des limites permissives
	# pour que le corps puisse vraiment s'affaisser à plat au sol.

	# Cou : ConeTwist avec cône de 80° (tête peut rouler sur le côté comme un cadavre)
	_make_cone(main, pos, body_basis, Vector3(0, 1.675, 0), head, torso_top, 80, 60)
	# Taille : ConeTwist avec cône de 70° (torse peut se plier fortement en avant/arrière/côté)
	_make_cone(main, pos, body_basis, Vector3(0, 0.975, 0), torso_top, pelvis, 70, 40)
	# Épaules : ConeTwist très permissif (bras peuvent pendouiller dans tous les sens)
	_make_cone(main, pos, body_basis, Vector3(-0.4, 1.225, 0), torso_top, upper_l, 120, 60)
	_make_cone(main, pos, body_basis, Vector3(0.4, 1.225, 0), torso_top, upper_r, 120, 60)
	# Coudes : Hinge qui plie de 0° à -150° (quasiment complet)
	_make_hinge(main, pos, body_basis, Vector3(-0.4, 0.825, 0), upper_l, lower_l, 0, -150)
	_make_hinge(main, pos, body_basis, Vector3(0.4, 0.825, 0), upper_r, lower_r, 0, -150)
	# Hanches : ConeTwist swing réduit de 100 à 60° pour empêcher les cuisses
	# de se replier totalement sous le corps sur tirs de loin (symptôme "tas
	# compact" persistant). 60° laisse encore une amplitude raisonnable pour
	# un cadavre sans tonus (un vivant fait ~45° max) sans aller jusqu'aux
	# flexions extrêmes qui pliaient le corps sur lui-même.
	_make_cone(main, pos, body_basis, Vector3(-0.15, 0.775, 0), pelvis, thigh_l, 60, 50)
	_make_cone(main, pos, body_basis, Vector3(0.15, 0.775, 0), pelvis, thigh_r, 60, 50)
	# Genoux : Hinge de 0° à 150° (quasiment complet)
	_make_hinge(main, pos, body_basis, Vector3(-0.15, 0.325, 0), thigh_l, calf_l, 150, 0)
	_make_hinge(main, pos, body_basis, Vector3(0.15, 0.325, 0), thigh_r, calf_r, 150, 0)

	# === COLLISION EXCEPTIONS : empêcher les parties adjacentes de se repousser ===
	# Sans ça, les collision shapes qui se chevauchent créent une force de répulsion qui
	# arrache les articulations. Avec les exceptions, les parties connectées peuvent se
	# toucher librement tout en restant liées par les joints. Exceptions aussi entre
	# parties non-connectées mais proches (ex: bras et torse) pour éviter les glitches.
	var all_parts = [head, torso_top, pelvis, upper_l, upper_r, lower_l, lower_r, thigh_l, thigh_r, calf_l, calf_r]
	for a in all_parts:
		for b in all_parts:
			if a != b:
				a.add_collision_exception_with(b)
	# Exception avec le player aussi pour tout le ragdoll (safety net contre le bug spawn-sous-map)
	var player_ref = main.player
	if player_ref != null and is_instance_valid(player_ref):
		for part in all_parts:
			part.add_collision_exception_with(player_ref)

	# === TRANSFERT DES FLÈCHES PLANTÉES vers torso_top ===
	for bolt in bolts:
		if is_instance_valid(bolt):
			bolt.reparent(torso_top)
	bolts.clear()

	# === IMPULSIONS : TRÉBUCHEMENT RÉALISTE (5 détails de réalisme) ===
	# 1. Asymétrie globale : chaque mort est unique (side_bias aléatoire)
	# 2. Ciseau des jambes : les 2 jambes ne partent pas pareil (décalage latéral)
	# 3. Whiplash tête : la tête fouette plus loin que le torse
	# 4. Retard des extrémités : mains et pieds recevront leur impulsion 80ms plus tard
	# 5. Angular damping dynamique : faible au début, monte avec un timer (géré ailleurs)

	# Asymétrie globale : chaque mort a une signature unique.
	# Plages réduites de moitié (±0.15 au lieu de ±0.3, 0.95-1.05 au lieu
	# de 0.9-1.1) pour diminuer les cas extrêmes où plusieurs randoms
	# s'alignaient défavorablement et donnaient un mort chelou.
	# asym_factor en cascade sur push_mult+jump_mult+spin_amp affectait
	# 9 rigidbodies, donc son amplitude était critique.
	var side_bias = randf_range(-0.15, 0.15)
	var asym_factor = randf_range(0.95, 1.05)

	# ⚠️ PLUS DE PALIERS ! Interpolation continue avec courbe quadratique.
	# Avant: 3 paliers (force<0.5, 0.5-0.85, >0.85) créaient des sauts brutaux
	# Un tir à force=0.49 donnait jump=0.0, un tir à force=0.51 donnait jump=2.5
	# → comportement aléatoire selon qu'on passait ou non le palier.
	# Maintenant: courbe quadratique (force²) qui :
	# - Préserve la force d'impact des tirs proches (force=1.0 → max préservé)
	# - Garde les tirs proches spectaculaires (force=0.85 → ~95% du max)
	# - Atténue doucement vers les tirs de loin (force=0.3 → ~10% du max)
	# - Élimine les discontinuités, comportement 100% prévisible.
	var power_curve = force * force
	var push_mult: float = lerp(10.0, 16.0, power_curve) * asym_factor
	# jump_mult en LINÉAIRE (pas quadratique comme les autres) car la
	# quadratique pénalisait trop la mi-distance : corps ne sautait pas
	# assez → tas compact. Linéaire donne un saut suffisant à force=0.5
	# (lerp=1.75) tout en restant doux aux tirs de loin.
	# Max réduit de 3.5 à 2.5 pour que l'impact max (mi-distance, force=1.0
	# selon la courbe en cloche d'impact_force) soit moins violent.
	var jump_mult: float = lerp(0.0, 2.5, force) * asym_factor
	var spin_amp: float = lerp(0.5, 1.3, power_curve)
	# Jump en courbe SQRT(force) : boost mi-distance sans toucher bout portant.
	# Linéaire donnait encore trop peu de saut à force=0.5 (composante Y = 0.875
	# → vitesse verticale 0.22 m/s, corps se soulève à peine → tas compact).
	# Sqrt monte vite au début, se stabilise près du max → +41% de saut à
	# force=0.5, +19% à force=0.7, et force=1.0 reste inchangé.
	var jump_curve = sqrt(force)

	# Calcul des axes anatomiques pour les torques dirigés
	var lateral_axis = kb_world.cross(Vector3.UP).normalized()
	# Bascule arrière proportionnelle à force³ (cubique) : quasi-nulle pour tirs
	# de loin (évite le pont cambré / backflip quand les jambes ne suivent pas
	# à cause de leg_scoop_factor = force² qui les laisse scotchées au sol),
	# prononcée pour tirs proches. Cohérent avec jump_curve également cubique.
	var backfall_torque = lateral_axis * 8.0 * force * force * force  # bascule arrière

	# TORSO : recule + bascule arrière + léger biais latéral (asymétrie)
	var torso_side = lateral_axis * side_bias  # décalage latéral aléatoire
	var torso_impulse = kb_world * push_mult * force + Vector3(0, jump_mult * jump_curve, 0) + torso_side
	torso_top.apply_impulse(torso_impulse, Vector3(0, 0.3, 0))
	torso_top.apply_torque_impulse(backfall_torque + Vector3(
		randf_range(-spin_amp * 0.3, spin_amp * 0.3),
		randf_range(-spin_amp * 0.3, spin_amp * 0.3),
		randf_range(-spin_amp * 0.3, spin_amp * 0.3)
	) * force)

	# PELVIS : suit le torse, moins de bascule, même biais latéral
	pelvis.apply_impulse(kb_world * push_mult * force * 0.9 + Vector3(0, jump_mult * jump_curve * 0.5, 0) + torso_side * 0.7)
	pelvis.apply_torque_impulse(backfall_torque * 0.5)

	# HEAD : suit le torse avec léger whiplash proportionnel à force
	# On ne met plus d'impulsion × 1.4 (qui faisait plonger la tête et soulevait le
	# corps par réaction physique). Compensation masse : tête (1.5 kg) reçoit
	# moins d'impulsion pour ne pas avoir une vitesse 2.67× plus grande que le
	# torse (4.0 kg) — sinon la tête s'arrache en avant et compresse le corps
	# derrière. Lerp(0.4, 1.0, force) : inchangé à portée proche (whiplash
	# spectaculaire préservé), réduit à mi-portée où le problème apparaissait.
	# Compensation masse tête en QUADRATIQUE : cible spécifiquement le problème
	# mi-distance. Avec linéaire, à force=0.5 la compensation était 0.65 →
	# ratio vitesse tête/torse = 1.73× → cou s'étire → corps compresse en tas.
	# Avec quadratique, à force=0.5 compensation=0.475 → ratio=1.27× (naturel).
	# À force=1.0 : compensation=1.0 inchangé (whiplash spectaculaire préservé).
	var head_mass_compensation = lerp(0.3, 1.0, force * force)
	head.apply_impulse(kb_world * push_mult * force * head_mass_compensation + Vector3(0, jump_mult * jump_curve * 0.2, 0) + torso_side)
	# Torque tête : réduit et contrôlé pour éviter que la tête pique vers le sol
	# par hasard (ce qui faisait soulever le corps). Axe Y seulement (rotation
	# horizontale) + très légère variation pour garder un peu de naturel.
	head.apply_torque_impulse(backfall_torque * 0.7 + Vector3(randf_range(-0.15, 0.15), randf_range(-0.3, 0.3), randf_range(-0.15, 0.15)) * force)

	# JAMBES : EFFET CISEAU (les 2 jambes partent de manière différente)
	# Une jambe part un peu plus vers le côté, l'autre un peu plus haut → ciseau naturel
	# Le scissor_offset varie aléatoirement : parfois gauche devance, parfois droite
	# IMPORTANT : le fauchage arrière (vers shooter) est aussi atténué par une courbe
	# sur les tirs de loin. À distance, le corps ne fait pas de "tapis tiré" spectaculaire,
	# il suit juste la direction de l'impact comme un vrai cadavre mou.
	var scissor_dir = 1.0 if randf() > 0.5 else -1.0  # quelle jambe devance
	var scissor_offset = lateral_axis * 0.8 * scissor_dir  # décalage latéral entre L et R
	# Fauchage atténué : sur tirs de loin, les jambes suivent la direction du tir
	# au lieu de partir vers le shooter. force < 0.5 → force_leg ~0 (suivent push)
	var leg_scoop_factor = force * force  # 0.3→0.09, 0.7→0.49, 1.0→1.0
	var leg_base = -kb_world * push_mult * force * 0.7 * leg_scoop_factor
	# Jambe L : un peu plus haute, un peu moins latérale
	var leg_l_push = leg_base + Vector3(0, jump_mult * jump_curve * 1.7, 0) + scissor_offset * 0.6 * force
	# Jambe R : un peu moins haute, un peu plus latérale (dans l'autre sens)
	var leg_r_push = leg_base + Vector3(0, jump_mult * jump_curve * 1.3, 0) - scissor_offset * 0.6 * force
	thigh_l.apply_impulse(leg_l_push)
	thigh_r.apply_impulse(leg_r_push)
	calf_l.apply_impulse(leg_l_push * 1.1)
	calf_r.apply_impulse(leg_r_push * 1.1)
	thigh_l.apply_torque_impulse(Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.3), randf_range(-0.5, 0.5)) * force)
	thigh_r.apply_torque_impulse(Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.3), randf_range(-0.5, 0.5)) * force)
	# Calfs : torques aléatoires en quadratique sur la force. Sur tirs de loin
	# (force ~0.2), les mollets étaient encore assez agités pour fouetter vers
	# le haut et finir en position chelou (jambes remontent, position finale
	# non naturelle, variabilité). Quadratique = quasi-nul à portée max,
	# inchangé à portée proche.
	calf_l.apply_torque_impulse(Vector3(randf_range(-0.8, 0.8), randf_range(-0.3, 0.3), randf_range(-0.8, 0.8)) * force * force)
	calf_r.apply_torque_impulse(Vector3(randf_range(-0.8, 0.8), randf_range(-0.3, 0.3), randf_range(-0.8, 0.8)) * force * force)

	# BRAS : asymétriques aussi (un bras ballotte plus que l'autre)
	var arm_asym_l = randf_range(0.7, 1.2)
	var arm_asym_r = randf_range(0.7, 1.2)
	upper_l.apply_impulse(kb_world * 0.6 * force * arm_asym_l + Vector3(0, 0.2 * force, 0))
	upper_r.apply_impulse(kb_world * 0.6 * force * arm_asym_r + Vector3(0, 0.2 * force, 0))
	lower_l.apply_impulse(kb_world * 0.5 * force * arm_asym_l)
	lower_r.apply_impulse(kb_world * 0.5 * force * arm_asym_r)
	upper_l.apply_torque_impulse(Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)) * force)
	upper_r.apply_torque_impulse(Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)) * force)
	lower_l.apply_torque_impulse(Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)) * force)
	lower_r.apply_torque_impulse(Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)) * force)

	# === DÉTAIL #4 : RETARD DES EXTRÉMITÉS (inertie naturelle) ===
	# 80ms après le coup, on donne une petite impulsion supplémentaire aux mains
	# et aux pieds. Comme si ces extrémités "suivaient avec retard" le reste du
	# corps par inertie. Crée l'effet "ragdoll vivant" typique des jeux AAA.
	# IMPORTANT : on utilise main.get_tree() car self (enemy) sera queue_free après.
	var delayed_parts = [lower_l, lower_r, calf_l, calf_r]
	var delay_impulse = kb_world * 2.0 * force
	main.get_tree().create_timer(0.08).timeout.connect(func():
		for p in delayed_parts:
			if is_instance_valid(p):
				p.apply_impulse(delay_impulse)
	)

	# === DÉTAIL #5 : ANGULAR DAMPING DYNAMIQUE ===
	# Toutes les parties commencent avec un damping faible (bien libres pendant le vol)
	# puis 1.2s après, on augmente le damping pour que le corps se stabilise au sol
	# au lieu de continuer à ballotter éternellement. Effet "s'immobilise naturellement".
	var all_rb = [head, torso_top, pelvis, upper_l, upper_r, lower_l, lower_r, thigh_l, thigh_r, calf_l, calf_r]
	main.get_tree().create_timer(1.2).timeout.connect(func():
		for rb in all_rb:
			if is_instance_valid(rb):
				rb.linear_damp = rb.linear_damp + 0.8
				rb.angular_damp = rb.angular_damp + 2.0
	)

	# === DÉTAIL #6 : GRAVITÉ PROGRESSIVE (effet Euphoria "s'abandonne") ===
	# Au début : gravité normale 1.5x (le corps vole, garde un peu de forme)
	# Après 0.3s : gravité 2.2x (le corps commence à s'abandonner, pèse plus)
	# Après 0.6s : gravité 3.0x (effondrement total, corps complètement mou qui pèse lourd)
	# Effet : on sent le corps "perdre ses forces" progressivement, comme un vrai
	# corps qui passe de "vivant encore" à "complètement inconscient".
	# Gravité progressive modulée par force : sur tirs de loin (force faible),
	# on reste proche de 1.5 pour que la tête ne plante pas trop fort au sol
	# (ce qui soulevait le corps par effet de levier et faisait partir les
	# membres en l'air de façon molle). Sur tirs proches, comportement inchangé.
	main.get_tree().create_timer(0.3).timeout.connect(func():
		for rb in all_rb:
			if is_instance_valid(rb):
				rb.gravity_scale = lerp(1.5, 2.2, force)
	)
	main.get_tree().create_timer(0.6).timeout.connect(func():
		for rb in all_rb:
			if is_instance_valid(rb):
				rb.gravity_scale = lerp(1.5, 3.0, force)
	)

	# === DÉTAIL #7 : ACCUEIL DU SOL (pic de friction à l'atterrissage) ===
	# 2.5s après la mort, le corps devrait avoir eu le temps de VRAIMENT finir son
	# effondrement naturel. À ce moment on augmente le damping pour stopper les
	# ballottements résiduels sans figer le corps en position bizarre.
	# Valeurs modérées (1.0 / 2.0) au lieu de fortes (2.0 / 4.0) pour que le corps
	# puisse continuer à s'affaisser légèrement s'il est dans une position instable.
	main.get_tree().create_timer(2.5).timeout.connect(func():
		for rb in all_rb:
			if is_instance_valid(rb):
				rb.linear_damp = 1.0
				rb.angular_damp = 2.0
	)

	# === DÉTAIL #9 : CORRECTION DOUCE DES ANGLES EXTRÊMES (LOW-RISK) ===
	# 2.5s après la mort (après le damping augmenté du DÉTAIL #7), on check les
	# paires de membres articulés pour détecter des angles extrêmes (bras/jambes
	# pliés dans des angles impossibles). Si détecté, on applique une petite
	# impulsion angulaire pour "déblock" le membre vers une position plus
	# naturelle, sans téléportation ni changement des joints/masses/collisions.
	#
	# Critère : angle entre basis Y des 2 RB > seuil (ex: 140° entre upper_arm
	# et lower_arm → coude plié trop fort).
	# Correction : torque impulse léger sur le membre "aval" pour relâcher.
	#
	# SAFE : ne touche aucune physique existante. Si ça foire, supprimer ce bloc.
	var check_delay = 2.5
	var correction_pairs = [
		{"a": upper_l, "b": lower_l, "threshold_deg": 140.0, "torque": 2.5},  # Coude G
		{"a": upper_r, "b": lower_r, "threshold_deg": 140.0, "torque": 2.5},  # Coude D
		{"a": thigh_l, "b": calf_l,  "threshold_deg": 140.0, "torque": 3.0},  # Genou G
		{"a": thigh_r, "b": calf_r,  "threshold_deg": 140.0, "torque": 3.0},  # Genou D
	]
	main.get_tree().create_timer(check_delay).timeout.connect(func():
		for pair in correction_pairs:
			var a = pair["a"]
			var b = pair["b"]
			if not is_instance_valid(a) or not is_instance_valid(b):
				continue
			# Angle entre les axes Y locaux des 2 RB
			var axis_a = a.global_transform.basis.y.normalized()
			var axis_b = b.global_transform.basis.y.normalized()
			var dot = clamp(axis_a.dot(axis_b), -1.0, 1.0)
			var angle_deg = rad_to_deg(acos(dot))
			# Note : si les axes pointent en sens opposés (membre quasi-replié
			# sur lui-même), l'angle est proche de 180°. Seuil 140° = membre
			# vraiment trop plié.
			if angle_deg > pair["threshold_deg"]:
				# Impulsion de correction : torque dans la direction qui
				# "ouvre" l'articulation (cross product des 2 axes)
				var correction_axis = axis_a.cross(axis_b).normalized()
				if correction_axis.length() > 0.01:
					var torque_strength = pair["torque"]
					b.apply_torque_impulse(correction_axis * torque_strength)
	)

	# === DÉTAIL #8 : NUAGE DE POUSSIÈRE À L'ATTERRISSAGE (INTENSIFIÉ) ===
	# 0.4s après la mort, le corps a touché le sol. On spawn ~30 cubes voxel
	# beige autour du pelvis, qui partent en dispersion radiale LARGE +
	# soulèvement + dissipation. Effet renforcé : plus de particules, plage
	# de tailles plus large, portée plus grande, durée plus longue.
	# Particules enfant de main, tween sur la particule elle-même.
	var pelvis_ref = pelvis
	var floor_y = pos.y
	var main_ref = main
	main.get_tree().create_timer(0.4).timeout.connect(func():
		if not is_instance_valid(main_ref):
			return
		# Centre du nuage : sous le pelvis (si encore valide) ou position de spawn
		var cx = pos.x
		var cz = pos.z
		if is_instance_valid(pelvis_ref):
			cx = pelvis_ref.global_position.x
			cz = pelvis_ref.global_position.z
		var dust_center = Vector3(cx, floor_y + 0.02, cz)
		for i in range(30):
			var p = MeshInstance3D.new()
			var pm = BoxMesh.new()
			var sz = randf_range(0.08, 0.22)
			pm.size = Vector3(sz, sz, sz)
			var mat = StandardMaterial3D.new()
			# Beige terreux avec plus de variation (plus clair / plus foncé)
			mat.albedo_color = Color(
				randf_range(0.65, 0.85),
				randf_range(0.55, 0.74),
				randf_range(0.40, 0.58)
			)
			mat.roughness = 1.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			pm.material = mat
			p.mesh = pm
			main_ref.add_child(p)
			# Position initiale : dispersion un peu plus large autour du pelvis
			var angle = randf() * TAU
			var r0 = randf_range(0.0, 0.7)
			p.global_position = dust_center + Vector3(cos(angle) * r0, 0.05, sin(angle) * r0)
			p.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
			# Dispersion radiale LARGE (jusqu'à 1.8m) + soulèvement jusqu'à 1.3m
			var radial = Vector3(cos(angle), 0, sin(angle))
			var final_pos = p.global_position + radial * randf_range(0.8, 1.8) + Vector3(0, randf_range(0.6, 1.3), 0)
			var dur = randf_range(0.8, 1.3)
			var tw = p.create_tween()
			tw.set_parallel(true)
			tw.tween_property(p, "global_position", final_pos, dur).set_ease(Tween.EASE_OUT)
			tw.tween_property(p, "scale", Vector3.ZERO, dur).set_ease(Tween.EASE_IN)
			tw.chain().tween_callback(p.queue_free)
	)

	# NOTE : l'ActiveRagdoll a été testé mais désactivé car la réduction de
	# puissance de la cloche (push 22→16, jump 3.5→2.5) a résolu le vrai
	# problème de mi-distance. Le fichier active_ragdoll.gd reste disponible
	# si besoin de repasser à cette approche plus tard.

# Helper pour créer un RigidBody3D avec sa collision. Simplifie massivement
# la création des 9 corps du ragdoll (évite 9x le même boilerplate).
# - parent_pos : position world du pied de l'ennemi (= pos passée à _spawn_physical_ragdoll)
# - basis : orientation world de l'ennemi
# - local_offset : où placer le pivot du RB par rapport à pos (en coords body, avant rotation)
# - mass : masse du RB en kg
# - col_size : taille Vec3 du BoxShape3D de collision
# - col_offset : décalage local de la collision par rapport au pivot du RB
# - lin_damp, ang_damp : amortissement (plus bas = plus "mou" / réactif)
func _make_rb(parent: Node, parent_pos: Vector3, basis: Basis, local_offset: Vector3, mass: float, col_size: Vector3, col_offset: Vector3, lin_damp: float, ang_damp: float) -> RigidBody3D:
	var rb = RigidBody3D.new()
	rb.mass = mass
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.linear_damp = lin_damp
	rb.angular_damp = ang_damp
	# Gravité 1.5x plus forte pour les ragdolls → légèrement plus lourde que la normale
	# mais pas trop, sinon le corps retombe trop vite et ne recule pas assez.
	# Le player vivant n'est PAS affecté (il utilise son propre gravity_force dans player.gd).
	rb.gravity_scale = 1.5
	parent.add_child(rb)
	rb.global_transform = Transform3D(basis, parent_pos + basis * local_offset)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = col_size
	col.shape = shape
	col.position = col_offset
	rb.add_child(col)
	return rb

# Helper HINGE (charnière 1 axe) : idéal pour coudes, genoux, taille.
# L'axe de rotation est l'axe X du joint (orientation passée via basis).
# upper/lower en radians définissent les limites anatomiques.
func _make_hinge(parent: Node, parent_pos: Vector3, basis: Basis, local_pos: Vector3, node_a: RigidBody3D, node_b: RigidBody3D, upper_deg: float, lower_deg: float):
	var joint = HingeJoint3D.new()
	parent.add_child(joint)
	joint.global_transform = Transform3D(basis, parent_pos + basis * local_pos)
	joint.node_a = node_a.get_path()
	joint.node_b = node_b.get_path()
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(upper_deg))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(lower_deg))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.9)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_BIAS, 0.3)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_RELAXATION, 1.0)

# Helper CONE-TWIST (cône avec torsion) : idéal pour épaules, hanches, cou.
# swing_deg = amplitude du cône (combien le membre peut s'écarter de l'axe)
# twist_deg = torsion autour de l'axe
func _make_cone(parent: Node, parent_pos: Vector3, basis: Basis, local_pos: Vector3, node_a: RigidBody3D, node_b: RigidBody3D, swing_deg: float, twist_deg: float):
	var joint = ConeTwistJoint3D.new()
	parent.add_child(joint)
	joint.global_transform = Transform3D(basis, parent_pos + basis * local_pos)
	joint.node_a = node_a.get_path()
	joint.node_b = node_b.get_path()
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing_deg))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist_deg))
	joint.set_param(ConeTwistJoint3D.PARAM_BIAS, 0.3)
	joint.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
	joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)

# ANCIEN helper PinJoint3D (gardé au cas où mais plus utilisé)
func _make_joint(parent: Node, parent_pos: Vector3, basis: Basis, local_pos: Vector3, node_a: RigidBody3D, node_b: RigidBody3D):
	var joint = PinJoint3D.new()
	parent.add_child(joint)
	joint.global_position = parent_pos + basis * local_pos
	joint.node_a = node_a.get_path()
	joint.node_b = node_b.get_path()
	joint.set_param(PinJoint3D.PARAM_BIAS, 0.95)
	joint.set_param(PinJoint3D.PARAM_DAMPING, 1.0)
	joint.set_param(PinJoint3D.PARAM_IMPULSE_CLAMP, 0.0)
