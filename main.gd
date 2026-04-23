# ============================================
# MAIN.GD — Scène racine, environnement, map voxel, décor, spawns
# ============================================
# FONCTIONS (cherche par Ctrl+F sur le nom) :
#   _ready()                          → Lance setup complet du monde
#   setup_env()                       → Sky, brouillard, lune, ambiance sombre
#   _mat(c, r, m)                     → Helper : material standard
#   _emissive_mat(c, e_col, e_power)  → Helper : material avec glow (torches, yeux)
#   _cube(parent, pos, size, mat)     → Helper : cube SANS collision
#   _cube_solid(parent, pos, size, mat) → Helper : cube AVEC collision (StaticBody3D)
#   gen_map()                         → Génère grille map tiles (herbe/terre/pierre)
#   build_world()                     → Pose tous les éléments (sol, décor, mobs)
#   _voxel_tree(p)                    → Arbre voxel (tronc + feuilles)
#   _voxel_rock(p)                    → Rocher voxel
#   _voxel_iron(p)                    → Minerai de fer
#   _voxel_water(p)                   → Tuile d'eau (rivière)
#   _voxel_bridge(p)                  → Pont SOLIDE marchable au-dessus rivière
#   _voxel_castle(p, c)               → Château médiéval (tours + crénelures)
#   _voxel_table(p)                   → (retiré, remplacé par les 5 tables de craft)
#   _spawn_craft_halo(parent, locked) → Helper halo doré/rouge selon verrou
#   _voxel_forge(p, kills)            → Table 1 : Forge (armes mêlée, kills 0)
#   _voxel_crossbow_bench(p, kills)   → Table 2 : Arbalétrier (distance, kills 5)
#   _voxel_workbench(p, kills)        → Table 3 : Établi (outils, kills 10)
#   _voxel_tannery(p, kills)          → Table 4 : Tannerie (armure cuir, kills 15)
#   _voxel_altar(p, kills)            → Table 5 : Autel (magie, kills 25)
#   is_on_river(p)                    → Check si position est sur rivière (strict)
#   is_near_river(p, margin)          → Check avec marge de sécurité
#   build_decor()                     → Pose tentes, feux, torches, barricades
#   _voxel_tent(p, red)               → Tente de camp
#   _voxel_banner(p, red)             → Bannière sur poteau
#   _voxel_campfire(p)                → Feu de camp avec flammes
#   _voxel_torch(p)                   → Torche avec glow émissif
#   _voxel_shield(p)                  → Bouclier décor au sol
#   _voxel_helmet(p)                  → Heaume décor au sol
#   _voxel_sword(p)                   → Épée plantée au sol
#   _voxel_arrow(p)                   → Flèche plantée décor
#   _voxel_corpse(p)                  → Cadavre décor
#   _voxel_barrel(p)                  → Tonneau
#   _voxel_crate(p)                   → Caisse en bois
#   _voxel_stake(p)                   → Pieu défensif
#   spawn_player()                    → Spawn le joueur dans la map
#   spawn_hud()                       → Instancie le HUD
#   start_wave()                      → Spawn des ennemis pour la wave
#   _process(d)                       → Boucle principale (torches flicker)
#
# CONSTANTES / REFS IMPORTANTES :
#   TS (3.0)                          → Tile Size, taille d'une tuile de map
#   MW (40) / MH (30)                 → Map Width/Height en tuiles
#   map[]                             → Grille 2D de la map
#   player                            → Réf du joueur spawné
#   torches[]                         → Refs torches pour flicker animation
#   wave (1)                          → Numéro de wave actuelle
# ============================================

extends Node3D
const TS = 3.0
const MW = 40
const MH = 30
var map := []
var enemies := []
var wave := 0
var kills := 0
var game_running := false
var world_objects := []
var torches := []
var player: CharacterBody3D

# Palette sombre
const COL_GRASS = Color(0.22, 0.28, 0.13)
const COL_DIRT = Color(0.25, 0.17, 0.1)
const COL_STONE = Color(0.38, 0.38, 0.4)
const COL_STONE_DARK = Color(0.28, 0.28, 0.3)
const COL_WOOD = Color(0.3, 0.2, 0.1)
const COL_WOOD_DARK = Color(0.2, 0.13, 0.06)
const COL_LEAF = Color(0.18, 0.25, 0.1)
const COL_METAL = Color(0.25, 0.25, 0.28)
const COL_IRON = Color(0.4, 0.42, 0.45)
const COL_WATER = Color(0.1, 0.15, 0.22)
const COL_CLOTH_RED = Color(0.42, 0.15, 0.1)
const COL_CLOTH_GREEN = Color(0.22, 0.28, 0.15)
const COL_BLOOD = Color(0.35, 0.08, 0.05)
const COL_GOLD = Color(0.55, 0.45, 0.15)

func _ready():
	setup_env()
	gen_map()
	build_world()
	build_decor()
	spawn_player()
	spawn_hud()
	game_running = true
	start_wave()

func setup_env():
	var env = WorldEnvironment.new()
	var e = Environment.new()
	# Dark cloudy sky
	e.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sm = ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.18, 0.2, 0.25)
	sm.sky_horizon_color = Color(0.3, 0.3, 0.32)
	sm.ground_bottom_color = Color(0.1, 0.1, 0.08)
	sm.ground_horizon_color = Color(0.2, 0.2, 0.18)
	sm.sun_angle_max = 60.0
	sm.sun_curve = 0.2
	sky.sky_material = sm
	e.sky = sky
	# Dense grey fog
	e.fog_enabled = true
	e.fog_light_color = Color(0.35, 0.35, 0.4)
	e.fog_light_energy = 0.7
	e.fog_density = 0.015
	e.fog_sky_affect = 0.4
	e.fog_aerial_perspective = 0.7
	# Low ambient
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.4, 0.5)
	e.ambient_light_energy = 0.6
	# Glow for fires and emissive
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.15
	env.environment = e
	add_child(env)
	# Moon-like diffuse light
	var sun = DirectionalLight3D.new()
	sun.light_color = Color(0.75, 0.82, 0.95)
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-55, 45, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.03
	add_child(sun)

func _mat(c: Color, r:=0.85, m:=0.0) -> StandardMaterial3D:
	var mt = StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = r
	mt.metallic = m
	return mt

func _emissive_mat(c: Color, e_col: Color, e_power:=2.0) -> StandardMaterial3D:
	var mt = StandardMaterial3D.new()
	mt.albedo_color = c
	mt.emission_enabled = true
	mt.emission = e_col
	mt.emission_energy_multiplier = e_power
	return mt

func _cube(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var c = MeshInstance3D.new()
	var m = BoxMesh.new()
	m.size = size
	m.material = mat
	c.mesh = m
	c.position = pos
	parent.add_child(c)
	return c

# Cube visuel + collision (bloque le joueur et plante les flèches)
func _cube_solid(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var c = _cube(parent, pos, size, mat)
	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.position = pos
	body.add_child(col)
	parent.add_child(body)
	return c

func gen_map():
	map = []
	for z in range(MH):
		var row = []
		for x in range(MW):
			var t = 0
			if x == MW/2 or x == MW/2-1: t = 3
			if t == 3 and z % 5 == 0: t = 5
			if abs(x - MW/2) < 3 and abs(z - MH/2) < 4: t = 0
			if t == 0 and randf() < 0.08 and x > 2 and x < MW-2 and abs(x - MW/2) > 3: t = 1
			if t == 0 and randf() < 0.05 and abs(x - MW/2) > 3: t = 2
			if t == 0 and randf() < 0.025 and (x < 10 or x > MW-10): t = 4
			row.append(t)
		map.append(row)

func build_world():
	# Ground plane dark earth
	var gm = PlaneMesh.new()
	gm.size = Vector2(MW * TS, MH * TS)
	gm.material = _mat(COL_DIRT, 0.98)
	var g = MeshInstance3D.new()
	g.mesh = gm
	g.position = Vector3(MW * TS / 2.0, 0, MH * TS / 2.0)
	add_child(g)
	# Ground collision
	var gb = StaticBody3D.new()
	var gc = CollisionShape3D.new()
	var gs = BoxShape3D.new()
	gs.size = Vector3(MW * TS, 0.4, MH * TS)
	gc.shape = gs
	gb.add_child(gc)
	gb.position = Vector3(MW * TS / 2.0, -0.2, MH * TS / 2.0)
	add_child(gb)
	# Voxel ground tiles (grid-aligned, some raised)
	var tile_mat_grass = _mat(COL_GRASS, 0.95)
	var tile_mat_grass2 = _mat(Color(0.19, 0.24, 0.1), 0.95)
	var tile_mat_dirt = _mat(Color(0.22, 0.15, 0.08), 0.98)
	for z in range(0, MH, 2):
		for x in range(0, MW, 2):
			if randf() < 0.35:
				var p = Vector3(x * TS + randf_range(-0.5, 0.5), 0, z * TS + randf_range(-0.5, 0.5))
				var sz = Vector3(TS * randf_range(1.2, 1.8), 0.04, TS * randf_range(1.2, 1.8))
				var m = tile_mat_grass if randf() > 0.5 else tile_mat_grass2
				if randf() < 0.3: m = tile_mat_dirt
				_cube(self, p + Vector3(0, 0.02, 0), sz, m)
	# Stone patches (grid aligned)
	for i in range(18):
		var cx = randi_range(2, MW - 3) * TS
		var cz = randi_range(2, MH - 3) * TS
		var tiles = randi_range(2, 5)
		for j in range(tiles):
			var p = Vector3(cx + randf_range(-1.5, 1.5), 0, cz + randf_range(-1.5, 1.5))
			var sz = Vector3(randf_range(0.8, 1.5), randf_range(0.08, 0.12), randf_range(0.8, 1.5))
			_cube(self, p + Vector3(0, sz.y / 2, 0), sz, _mat(COL_STONE_DARK, 0.9))
	# Map tiles
	for z in range(MH):
		for x in range(MW):
			var t = map[z][x]
			var p = Vector3(x * TS, 0, z * TS)
			if t == 1: _voxel_tree(p)
			elif t == 2: _voxel_rock(p)
			elif t == 3: _voxel_water(p)
			elif t == 4: _voxel_iron(p)
			elif t == 5: _voxel_bridge(p)
	_voxel_castle(Vector3(5*TS, 0, MH/2*TS), COL_STONE)
	_voxel_castle(Vector3((MW-6)*TS, 0, MH/2*TS), COL_STONE_DARK)
	# ─── 5 TABLES DE CRAFT en cercle autour du centre ───
	# Chaque table a un seuil "kills_required" pour se débloquer (0/5/10/15/25)
	# et un type spécifique (armes/distance/outils/armure/magie).
	# Positionnées en cercle autour du centre de la map, rayon ~8m.
	var center = Vector3(MW/2*TS, 0, MH/2*TS)
	var circle_r = 8.0
	# Forge (kills 0) — ANGLE 0° (nord)
	_voxel_forge(center + Vector3(0, 0, -circle_r), 0)
	# Arbalétrier (kills 5) — ANGLE 72°
	_voxel_crossbow_bench(center + Vector3(cos(deg_to_rad(-18)) * circle_r, 0, sin(deg_to_rad(-18)) * circle_r), 5)
	# Établi (kills 10) — ANGLE 144°
	_voxel_workbench(center + Vector3(cos(deg_to_rad(54)) * circle_r, 0, sin(deg_to_rad(54)) * circle_r), 10)
	# Tannerie (kills 15) — ANGLE 216°
	_voxel_tannery(center + Vector3(cos(deg_to_rad(126)) * circle_r, 0, sin(deg_to_rad(126)) * circle_r), 15)
	# Autel (kills 25) — ANGLE 288°
	_voxel_altar(center + Vector3(cos(deg_to_rad(198)) * circle_r, 0, sin(deg_to_rad(198)) * circle_r), 25)

func _voxel_tree(p: Vector3):
	var t = Node3D.new()
	t.position = p
	# Trunk (stack of cubes)
	var h = randi_range(3, 5)
	var trunk_mat = _mat(COL_WOOD_DARK, 0.95)
	for i in range(h):
		var wobble = Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03))
		_cube(t, Vector3(0, 0.25 + i * 0.5, 0) + wobble, Vector3(0.45, 0.5, 0.45), trunk_mat)
	# Leaves (cluster of cubes)
	var leaf_mat = _mat(COL_LEAF, 0.9)
	var leaf_mat2 = _mat(Color(0.15, 0.22, 0.08), 0.9)
	var top_y = h * 0.5 + 0.35
	var offs = [
		Vector3(0, 0, 0), Vector3(0.7, 0, 0), Vector3(-0.7, 0, 0),
		Vector3(0, 0, 0.7), Vector3(0, 0, -0.7),
		Vector3(0, 0.7, 0), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5),
		Vector3(0, -0.5, 0.5), Vector3(0.5, -0.3, 0)
	]
	for o in offs:
		var m = leaf_mat if randf() > 0.4 else leaf_mat2
		_cube(t, Vector3(0, top_y, 0) + o, Vector3(0.7, 0.7, 0.7), m)
	# Collision (trunk)
	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var cs = CylinderShape3D.new()
	cs.radius = 0.3
	cs.height = h * 0.5
	col.shape = cs
	col.position.y = h * 0.25
	body.add_child(col)
	t.add_child(body)
	# Collision feuilles (pour planter flèches — sphérique englobante)
	var body2 = StaticBody3D.new()
	var col2 = CollisionShape3D.new()
	var ls = SphereShape3D.new()
	ls.radius = 1.0
	col2.shape = ls
	col2.position.y = top_y
	body2.add_child(col2)
	t.add_child(body2)
	t.set_meta("type","tree")
	t.set_meta("hp",3)
	add_child(t)
	world_objects.append(t)

func _voxel_rock(p: Vector3):
	var r = Node3D.new()
	r.position = p
	var n = randi_range(3, 5)
	var mat = _mat(COL_STONE, 0.95)
	var mat2 = _mat(Color(0.32, 0.32, 0.34), 0.95)
	for i in range(n):
		var sz = Vector3(randf_range(0.4, 0.8), randf_range(0.3, 0.6), randf_range(0.4, 0.8))
		var pos = Vector3(randf_range(-0.5, 0.5), sz.y / 2, randf_range(-0.5, 0.5))
		var m = mat if randf() > 0.4 else mat2
		_cube_solid(r, pos, sz, m)
	r.set_meta("type","rock")
	r.set_meta("hp",4)
	add_child(r)
	world_objects.append(r)

func _voxel_iron(p: Vector3):
	var r = Node3D.new()
	r.position = p
	var mat = _mat(COL_IRON, 0.4, 0.7)
	var mat_glow = _emissive_mat(Color(0.6, 0.65, 0.7), Color(0.4, 0.5, 0.6), 1.5)
	_cube_solid(r, Vector3(0, 0.3, 0), Vector3(0.7, 0.6, 0.7), mat)
	_cube_solid(r, Vector3(0.3, 0.5, 0.2), Vector3(0.35, 0.35, 0.35), mat)
	_cube_solid(r, Vector3(-0.25, 0.45, -0.15), Vector3(0.3, 0.3, 0.3), mat_glow)
	_cube_solid(r, Vector3(0.15, 0.7, -0.2), Vector3(0.2, 0.2, 0.2), mat_glow)
	r.set_meta("type","iron")
	r.set_meta("hp",5)
	add_child(r)
	world_objects.append(r)

func _voxel_water(p: Vector3):
	var w = Node3D.new()
	w.position = p
	var mt = StandardMaterial3D.new()
	mt.albedo_color = Color(COL_WATER.r, COL_WATER.g, COL_WATER.b, 0.85)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.roughness = 0.1
	mt.metallic = 0.3
	_cube(w, Vector3(0, 0.1, 0), Vector3(TS, 0.2, TS), mt)
	add_child(w)

func _voxel_bridge(p: Vector3):
	var b = Node3D.new()
	b.position = p
	var wm = _mat(COL_WOOD, 0.95)
	var wm2 = _mat(COL_WOOD_DARK, 0.95)
	# Pont traversable : pas de collision (le sol dessous est déjà solide)
	_cube(b, Vector3(0, 0.08, 0), Vector3(TS, 0.08, TS), wm)
	# Planks detail
	for i in range(4):
		var m = wm if i % 2 == 0 else wm2
		_cube(b, Vector3(0, 0.16, -1.0 + i * 0.67), Vector3(TS * 0.95, 0.04, 0.5), m)
	add_child(b)

func _voxel_castle(p: Vector3, c: Color):
	var castle = Node3D.new()
	castle.position = p
	var wall_mat = _mat(c, 0.9)
	var wall_mat_dark = _mat(Color(c.r * 0.75, c.g * 0.75, c.b * 0.75), 0.9)
	# 4 towers
	for i in range(4):
		var a = i * PI / 2
		var tx = cos(a) * 4
		var tz = sin(a) * 4
		# Tower stack
		var th = 8
		for j in range(th):
			var m = wall_mat if j % 2 == 0 else wall_mat_dark
			_cube_solid(castle, Vector3(tx, 0.5 + j * 0.7, tz), Vector3(1.4, 0.7, 1.4), m)
		# Crenellations
		for k in range(4):
			var ka = k * PI / 2
			_cube_solid(castle, Vector3(tx + cos(ka) * 0.55, 0.5 + th * 0.7, tz + sin(ka) * 0.55),
				Vector3(0.35, 0.4, 0.35), wall_mat)
	# Walls between towers
	for i in range(4):
		var a1 = i * PI / 2
		var a2 = (i + 1) * PI / 2
		var p1 = Vector3(cos(a1) * 4, 0, sin(a1) * 4)
		var p2 = Vector3(cos(a2) * 4, 0, sin(a2) * 4)
		var steps = 5
		for s in range(1, steps):
			var t = float(s) / steps
			var pos = p1.lerp(p2, t)
			for h in range(5):
				var m = wall_mat if (s + h) % 2 == 0 else wall_mat_dark
				_cube_solid(castle, Vector3(pos.x, 0.5 + h * 0.7, pos.z), Vector3(1.2, 0.7, 1.2), m)
	add_child(castle)

# Helper : spawn un halo doré plat au sol pour indiquer la zone de craft d'une table.
# Utilisé par les 5 tables de craft pour un look cohérent.
# `locked` = true → halo gris/rouge pour tables verrouillées (pas encore atteint le seuil kills)
func _spawn_craft_halo(parent: Node3D, locked: bool):
	var halo = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = 1.0
	tm.outer_radius = 1.3
	tm.rings = 48
	tm.ring_segments = 8
	var halo_mat = StandardMaterial3D.new()
	if locked:
		# Rouge sombre pour verrouillé
		halo_mat.albedo_color = Color(0.8, 0.25, 0.2, 0.35)
		halo_mat.emission = Color(0.8, 0.2, 0.15)
	else:
		# Doré pour débloqué
		halo_mat.albedo_color = Color(1.0, 0.78, 0.25, 0.35)
		halo_mat.emission = Color(1.0, 0.72, 0.20)
	halo_mat.emission_enabled = true
	halo_mat.emission_energy_multiplier = 0.9
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.material = halo_mat
	halo.mesh = tm
	halo.scale = Vector3(1.0, 0.02, 1.0)
	halo.position = Vector3(0, 0.03, 0)
	parent.add_child(halo)

# Forge (kills 0) : armes mêlée (épée, hache)
# Socle bois + ENCLUME fer + marteau + foyer avec braises rougeoyantes + lingots
func _voxel_forge(p: Vector3, kills_required: int):
	var t = Node3D.new()
	t.position = p
	t.add_to_group("craft_station")
	t.set_meta("craft_type", "forge")
	t.set_meta("kills_required", kills_required)
	var wm = _mat(COL_WOOD, 0.95)
	var wm_dark = _mat(COL_WOOD_DARK, 0.95)
	var metal = _mat(COL_METAL, 0.35, 0.75)
	var metal_dark = _mat(Color(0.18, 0.18, 0.2), 0.45, 0.7)
	var ember = _emissive_mat(Color(0.9, 0.3, 0.1), Color(1.0, 0.35, 0.08), 2.5)
	# Socle bois
	_cube_solid(t, Vector3(0, 0.25, 0), Vector3(1.6, 0.5, 1.0), wm_dark)
	for lx in [-0.7, 0.7]:
		for lz in [-0.4, 0.4]:
			_cube_solid(t, Vector3(lx, 0.05, lz), Vector3(0.15, 0.1, 0.15), wm_dark)
	# Enclume
	_cube_solid(t, Vector3(-0.2, 0.6, 0), Vector3(0.55, 0.12, 0.45), metal_dark)
	_cube_solid(t, Vector3(-0.2, 0.78, 0), Vector3(0.35, 0.18, 0.3), metal)
	_cube_solid(t, Vector3(-0.2, 0.95, 0), Vector3(0.75, 0.12, 0.4), metal)
	_cube_solid(t, Vector3(-0.65, 0.95, 0), Vector3(0.25, 0.1, 0.25), metal)
	# Marteau
	var hammer = Node3D.new()
	hammer.position = Vector3(-0.2, 1.05, 0)
	hammer.rotation = Vector3(0, 0.6, 0)
	_cube(hammer, Vector3(0.2, 0, 0), Vector3(0.18, 0.12, 0.14), metal)
	_cube(hammer, Vector3(-0.1, 0, 0), Vector3(0.35, 0.06, 0.06), wm)
	t.add_child(hammer)
	# Foyer
	var stone = _mat(Color(0.35, 0.32, 0.3), 0.95)
	_cube_solid(t, Vector3(0.6, 0.35, 0), Vector3(0.6, 0.2, 0.55), stone)
	_cube_solid(t, Vector3(0.6, 0.48, 0.25), Vector3(0.55, 0.1, 0.08), _mat(Color(0.28, 0.25, 0.23), 0.95))
	_cube_solid(t, Vector3(0.6, 0.48, -0.25), Vector3(0.55, 0.1, 0.08), _mat(Color(0.28, 0.25, 0.23), 0.95))
	_cube_solid(t, Vector3(0.85, 0.48, 0), Vector3(0.08, 0.1, 0.45), _mat(Color(0.28, 0.25, 0.23), 0.95))
	_cube(t, Vector3(0.55, 0.5, 0.05), Vector3(0.15, 0.08, 0.15), ember)
	_cube(t, Vector3(0.68, 0.5, -0.08), Vector3(0.12, 0.08, 0.12), ember)
	_cube(t, Vector3(0.48, 0.5, -0.1), Vector3(0.1, 0.06, 0.1), ember)
	var foyer_light = OmniLight3D.new()
	foyer_light.position = Vector3(0.6, 0.7, 0)
	foyer_light.light_color = Color(1.0, 0.5, 0.2)
	foyer_light.light_energy = 1.2
	foyer_light.omni_range = 3.0
	t.add_child(foyer_light)
	# Lingots
	_cube(t, Vector3(0.05, 0.52, -0.38), Vector3(0.2, 0.06, 0.1), metal)
	_cube(t, Vector3(0.15, 0.52, 0.38), Vector3(0.22, 0.06, 0.09), metal)
	# Halo doré au sol
	_spawn_craft_halo(t, kills_required > 0)
	add_child(t)

# Arbalétrier (kills 5) : armes à distance + munitions
# Établi long avec arbalète posée en travers + carreaux alignés + cible de bois
func _voxel_crossbow_bench(p: Vector3, kills_required: int):
	var t = Node3D.new()
	t.position = p
	t.add_to_group("craft_station")
	t.set_meta("craft_type", "crossbow_bench")
	t.set_meta("kills_required", kills_required)
	var wm = _mat(COL_WOOD, 0.95)
	var wm_dark = _mat(COL_WOOD_DARK, 0.95)
	var metal = _mat(COL_METAL, 0.35, 0.75)
	var string_mat = _mat(Color(0.7, 0.65, 0.5), 0.6)
	# Table (plateau + 4 pieds)
	_cube_solid(t, Vector3(0, 0.85, 0), Vector3(1.8, 0.12, 0.7), wm)
	for lx in [-0.8, 0.8]:
		for lz in [-0.28, 0.28]:
			_cube_solid(t, Vector3(lx, 0.42, lz), Vector3(0.12, 0.85, 0.12), wm_dark)
	# Arbalète posée en travers
	var xbow = Node3D.new()
	xbow.position = Vector3(0.15, 0.93, 0)
	xbow.rotation = Vector3(0, 1.2, 0)  # Diagonale
	# Corps
	_cube(xbow, Vector3(0, 0, 0), Vector3(0.7, 0.08, 0.1), wm_dark)
	# Arc horizontal (2 moitiés)
	_cube(xbow, Vector3(0.12, 0.03, -0.22), Vector3(0.05, 0.05, 0.3), wm)
	_cube(xbow, Vector3(0.12, 0.03, 0.22), Vector3(0.05, 0.05, 0.3), wm)
	# Corde
	_cube(xbow, Vector3(0.12, 0.03, 0), Vector3(0.02, 0.02, 0.7), string_mat)
	# Gâchette métal
	_cube(xbow, Vector3(-0.15, -0.05, 0), Vector3(0.05, 0.08, 0.06), metal)
	t.add_child(xbow)
	# 3 carreaux alignés sur le bord
	for i_c in range(3):
		var bolt = Node3D.new()
		bolt.position = Vector3(-0.6 + i_c * 0.15, 0.93, -0.25)
		_cube(bolt, Vector3(0, 0, 0), Vector3(0.03, 0.03, 0.4), wm_dark)
		_cube(bolt, Vector3(0, 0, 0.22), Vector3(0.05, 0.04, 0.08), metal)  # Pointe
		t.add_child(bolt)
	# Cible de tir rustique au fond (planche ronde en cubes)
	var target = Node3D.new()
	target.position = Vector3(-0.5, 1.4, 0.3)
	for ty in [-0.15, 0, 0.15]:
		_cube(target, Vector3(0, ty, 0), Vector3(0.45, 0.15, 0.06), wm)
	# Cercles concentriques colorés sur la cible
	_cube(target, Vector3(0, 0, 0.04), Vector3(0.35, 0.15, 0.02), _mat(Color(0.9, 0.9, 0.85), 0.9))
	_cube(target, Vector3(0, 0, 0.05), Vector3(0.22, 0.22, 0.01), _mat(Color(0.7, 0.15, 0.15), 0.9))
	_cube(target, Vector3(0, 0, 0.06), Vector3(0.08, 0.08, 0.01), _mat(Color(0.95, 0.95, 0.9), 0.9))
	t.add_child(target)
	# Halo
	_spawn_craft_halo(t, kills_required > 0)
	add_child(t)

# Établi (kills 10) : outils (pioche, hache, scie)
# Grande table avec planches empilées + scie + outils posés
func _voxel_workbench(p: Vector3, kills_required: int):
	var t = Node3D.new()
	t.position = p
	t.add_to_group("craft_station")
	t.set_meta("craft_type", "workbench")
	t.set_meta("kills_required", kills_required)
	var wm = _mat(COL_WOOD, 0.95)
	var wm_dark = _mat(COL_WOOD_DARK, 0.95)
	var metal = _mat(COL_METAL, 0.35, 0.75)
	# Plateau large + planches de surface
	_cube_solid(t, Vector3(0, 0.85, 0), Vector3(1.6, 0.12, 0.9), wm)
	for stripe_z in [-0.3, 0, 0.3]:
		_cube(t, Vector3(0, 0.92, stripe_z), Vector3(1.55, 0.02, 0.25), wm_dark)
	# Pieds croisés en X (rustique)
	for lx in [-0.7, 0.7]:
		_cube_solid(t, Vector3(lx, 0.42, -0.35), Vector3(0.12, 0.85, 0.12), wm_dark)
		_cube_solid(t, Vector3(lx, 0.42, 0.35), Vector3(0.12, 0.85, 0.12), wm_dark)
	# Traverse basse (renfort)
	_cube(t, Vector3(0, 0.2, 0), Vector3(1.5, 0.08, 0.08), wm_dark)
	# Tas de planches empilées à gauche
	for i_p in range(4):
		_cube(t, Vector3(-0.55, 0.95 + i_p * 0.06, 0.25), Vector3(0.5, 0.05, 0.15), wm)
	# Scie : lame + manche
	var saw = Node3D.new()
	saw.position = Vector3(0.3, 0.93, 0.0)
	saw.rotation = Vector3(0, 0.3, 0)
	# Manche bois
	_cube(saw, Vector3(-0.22, 0, 0), Vector3(0.15, 0.1, 0.06), wm_dark)
	# Lame métal (longue plaque fine)
	_cube(saw, Vector3(0.15, 0, 0), Vector3(0.5, 0.08, 0.015), metal)
	t.add_child(saw)
	# Pioche posée sur le bord droit
	var pick = Node3D.new()
	pick.position = Vector3(0.6, 0.95, -0.3)
	pick.rotation = Vector3(0, 0.9, 0)
	# Manche
	_cube(pick, Vector3(0, 0, 0), Vector3(0.06, 0.06, 0.55), wm)
	# Tête métal (en croix)
	_cube(pick, Vector3(0, 0.05, 0.2), Vector3(0.08, 0.08, 0.25), metal)
	t.add_child(pick)
	# Copeaux de bois au sol sous la table (ambiance atelier)
	for _i in range(6):
		var chip_pos = Vector3(randf_range(-0.6, 0.6), 0.04, randf_range(-0.35, 0.35))
		_cube(t, chip_pos, Vector3(0.06, 0.02, 0.04), wm)
	# Halo
	_spawn_craft_halo(t, kills_required > 0)
	add_child(t)

# Tannerie (kills 15) : armures cuir
# Châssis en bois vertical + peaux tendues + établi bas avec outils de tannerie
func _voxel_tannery(p: Vector3, kills_required: int):
	var t = Node3D.new()
	t.position = p
	t.add_to_group("craft_station")
	t.set_meta("craft_type", "tannery")
	t.set_meta("kills_required", kills_required)
	var wm = _mat(COL_WOOD, 0.95)
	var wm_dark = _mat(COL_WOOD_DARK, 0.95)
	var leather_light = _mat(Color(0.75, 0.55, 0.35), 0.95)
	var leather_dark = _mat(Color(0.5, 0.32, 0.18), 0.95)
	var metal = _mat(COL_METAL, 0.35, 0.75)
	# Établi bas (base)
	_cube_solid(t, Vector3(0, 0.4, 0), Vector3(1.4, 0.12, 0.7), wm)
	for lx in [-0.6, 0.6]:
		for lz in [-0.28, 0.28]:
			_cube_solid(t, Vector3(lx, 0.2, lz), Vector3(0.1, 0.4, 0.1), wm_dark)
	# Châssis vertical pour tendre les peaux (2 poteaux + barre haute)
	_cube_solid(t, Vector3(-0.65, 1.1, -0.2), Vector3(0.12, 1.4, 0.12), wm_dark)
	_cube_solid(t, Vector3(0.65, 1.1, -0.2), Vector3(0.12, 1.4, 0.12), wm_dark)
	_cube_solid(t, Vector3(0, 1.75, -0.2), Vector3(1.4, 0.1, 0.1), wm_dark)
	# Peaux tendues (2 grandes peaux sur le châssis)
	_cube(t, Vector3(-0.3, 1.25, -0.2), Vector3(0.5, 0.8, 0.04), leather_light)
	_cube(t, Vector3(0.3, 1.25, -0.2), Vector3(0.5, 0.8, 0.04), leather_dark)
	# Cordelettes qui tendent les peaux (petits cubes au bord)
	for py in [0.95, 1.55]:
		_cube(t, Vector3(-0.3, py, -0.18), Vector3(0.5, 0.02, 0.02), _mat(Color(0.4, 0.3, 0.2), 0.8))
		_cube(t, Vector3(0.3, py, -0.18), Vector3(0.5, 0.02, 0.02), _mat(Color(0.4, 0.3, 0.2), 0.8))
	# Sur la table : outils de tannerie (couteau + seau)
	# Couteau de tannerie (lame large, manche court)
	var knife = Node3D.new()
	knife.position = Vector3(-0.3, 0.47, 0.1)
	knife.rotation = Vector3(0, 0.4, 0)
	_cube(knife, Vector3(-0.12, 0, 0), Vector3(0.1, 0.05, 0.05), wm_dark)  # Manche
	_cube(knife, Vector3(0.08, 0, 0), Vector3(0.22, 0.04, 0.12), metal)    # Lame
	t.add_child(knife)
	# Seau en bois
	var bucket = Node3D.new()
	bucket.position = Vector3(0.4, 0.55, 0.1)
	# Parois du seau (4 côtés)
	for side in [[0.12, 0, 0], [-0.12, 0, 0], [0, 0, 0.12], [0, 0, -0.12]]:
		var pos = Vector3(side[0], 0, side[2])
		var size = Vector3(0.28, 0.22, 0.03) if side[0] != 0 else Vector3(0.03, 0.22, 0.28)
		_cube(bucket, pos, size, wm_dark)
	# Fond
	_cube(bucket, Vector3(0, -0.1, 0), Vector3(0.28, 0.02, 0.28), wm_dark)
	# Liquide brun (teinture) dans le seau
	_cube(bucket, Vector3(0, 0.05, 0), Vector3(0.25, 0.02, 0.25), _mat(Color(0.35, 0.18, 0.08), 0.5))
	t.add_child(bucket)
	# Halo
	_spawn_craft_halo(t, kills_required > 0)
	add_child(t)

# Autel (kills 25) : magie / objets rares
# Socle pierre ancienne + pierre runique émissive bleue + braises bleues +
# cristaux suspendus. Ambiance mystique.
func _voxel_altar(p: Vector3, kills_required: int):
	var t = Node3D.new()
	t.position = p
	t.add_to_group("craft_station")
	t.set_meta("craft_type", "altar")
	t.set_meta("kills_required", kills_required)
	var stone_dark = _mat(Color(0.22, 0.22, 0.25), 0.95)
	var stone_medium = _mat(Color(0.35, 0.33, 0.35), 0.95)
	var arcane_ember = _emissive_mat(Color(0.3, 0.5, 1.0), Color(0.3, 0.6, 1.0), 3.0)
	var crystal = _emissive_mat(Color(0.6, 0.4, 0.95), Color(0.5, 0.3, 1.0), 2.0)
	var rune_glow = _emissive_mat(Color(0.2, 0.5, 0.9), Color(0.2, 0.6, 1.0), 2.5)
	# Socle pierre en 2 étages
	_cube_solid(t, Vector3(0, 0.15, 0), Vector3(1.8, 0.3, 1.2), stone_dark)
	_cube_solid(t, Vector3(0, 0.4, 0), Vector3(1.4, 0.2, 0.9), stone_medium)
	_cube_solid(t, Vector3(0, 0.6, 0), Vector3(1.1, 0.15, 0.7), stone_dark)
	# Pierre runique centrale (monolithe émissif bleu)
	_cube_solid(t, Vector3(0, 1.15, 0), Vector3(0.35, 0.9, 0.35), stone_medium)
	# Runes glow sur les faces (petits cubes émissifs)
	_cube(t, Vector3(0.18, 1.1, 0), Vector3(0.02, 0.15, 0.08), rune_glow)
	_cube(t, Vector3(-0.18, 1.25, 0), Vector3(0.02, 0.1, 0.1), rune_glow)
	_cube(t, Vector3(0, 1.4, 0.18), Vector3(0.1, 0.08, 0.02), rune_glow)
	_cube(t, Vector3(0, 1.0, -0.18), Vector3(0.12, 0.1, 0.02), rune_glow)
	# Braises bleues magiques devant le monolithe
	_cube(t, Vector3(0, 0.72, 0.4), Vector3(0.12, 0.06, 0.12), arcane_ember)
	_cube(t, Vector3(-0.15, 0.72, 0.35), Vector3(0.08, 0.05, 0.08), arcane_ember)
	_cube(t, Vector3(0.2, 0.72, 0.35), Vector3(0.1, 0.05, 0.1), arcane_ember)
	# Cristaux violets suspendus (2 de chaque côté)
	_cube(t, Vector3(-0.7, 1.1, 0.2), Vector3(0.12, 0.18, 0.12), crystal)
	_cube(t, Vector3(0.7, 1.0, -0.2), Vector3(0.1, 0.22, 0.1), crystal)
	# Light magique bleue (glow ambiant)
	var altar_light = OmniLight3D.new()
	altar_light.position = Vector3(0, 1.2, 0)
	altar_light.light_color = Color(0.3, 0.6, 1.0)
	altar_light.light_energy = 1.5
	altar_light.omni_range = 4.0
	t.add_child(altar_light)
	# Halo
	_spawn_craft_halo(t, kills_required > 0)
	add_child(t)

# Check si une position est sur la rivière / pont (pour éviter le décor dessus)
func is_on_river(p: Vector3) -> bool:
	var tile_x = int(p.x / TS)
	return tile_x >= MW/2 - 1 and tile_x <= MW/2 + 1

# === DECOR ===

func build_decor():
	var total_w = MW * TS
	var total_h = MH * TS
	# Tents
	for i in range(8):
		var p = Vector3(randf_range(6, total_w - 6), 0, randf_range(6, total_h - 6))
		if p.distance_to(Vector3(MW/4*TS, 0, MH/2*TS)) < 8: continue
		if is_on_river(p): continue
		_voxel_tent(p, randf() > 0.5)
	# Banners on poles
	for i in range(8):
		var p = Vector3(randf_range(5, total_w - 5), 0, randf_range(5, total_h - 5))
		if is_on_river(p): continue
		_voxel_banner(p, i % 2 == 0)
	# Campfires
	for i in range(3):
		var p = Vector3(randf_range(8, total_w - 8), 0, randf_range(8, total_h - 8))
		if is_on_river(p): continue
		_voxel_campfire(p)
	# Torches
	for i in range(12):
		var p = Vector3(randf_range(5, total_w - 5), 0, randf_range(5, total_h - 5))
		if is_on_river(p): continue
		_voxel_torch(p)
	# Battlefield debris
	for i in range(30):
		var p = Vector3(randf_range(3, total_w - 3), 0, randf_range(3, total_h - 3))
		if is_on_river(p): continue
		var pick = randi() % 4
		match pick:
			0: _voxel_shield(p)
			1: _voxel_helmet(p)
			2: _voxel_sword(p)
			3: _voxel_arrow(p)
	# Corpses
	for i in range(10):
		var p = Vector3(randf_range(5, total_w - 5), 0, randf_range(5, total_h - 5))
		if is_on_river(p): continue
		_voxel_corpse(p)
	# Barrels
	for i in range(12):
		var p = Vector3(randf_range(5, total_w - 5), 0, randf_range(5, total_h - 5))
		if is_on_river(p): continue
		_voxel_barrel(p)
	# Crates
	for i in range(8):
		var p = Vector3(randf_range(5, total_w - 5), 0, randf_range(5, total_h - 5))
		if is_on_river(p): continue
		_voxel_crate(p)
	# Stake clusters
	for i in range(6):
		var center = Vector3(randf_range(10, total_w - 10), 0, randf_range(10, total_h - 10))
		if is_on_river(center): continue
		for j in range(randi_range(3, 6)):
			var sp = center + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			_voxel_stake(sp)

func _voxel_tent(p: Vector3, red: bool):
	var t = Node3D.new()
	t.position = p
	t.rotation.y = randi_range(0, 3) * PI / 2
	var col = COL_CLOTH_RED if red else COL_CLOTH_GREEN
	var mat = _mat(col, 0.95)
	var mat_dark = _mat(Color(col.r * 0.7, col.g * 0.7, col.b * 0.7), 0.95)
	# Pyramid of cubes
	for y in range(5):
		var w = 2.2 - y * 0.4
		var m = mat if y % 2 == 0 else mat_dark
		_cube(t, Vector3(0, 0.2 + y * 0.5, 0), Vector3(w, 0.5, w), m)
	# Center pole top
	_cube(t, Vector3(0, 3.0, 0), Vector3(0.15, 0.5, 0.15), _mat(COL_WOOD_DARK))
	# Pegs
	for i in range(4):
		var a = i * PI / 2
		_cube(t, Vector3(cos(a) * 1.5, 0.1, sin(a) * 1.5), Vector3(0.1, 0.2, 0.1), _mat(COL_WOOD_DARK))
	# Collision
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(2.0, 2.5, 2.0)
	coll.shape = cs
	coll.position.y = 1.25
	body.add_child(coll)
	t.add_child(body)
	add_child(t)

func _voxel_banner(p: Vector3, red: bool):
	var b = Node3D.new()
	b.position = p
	# Pole
	for i in range(8):
		_cube(b, Vector3(0, 0.3 + i * 0.55, 0), Vector3(0.15, 0.55, 0.15), _mat(COL_WOOD_DARK))
	# Flag
	var flag_col = COL_CLOTH_RED if red else Color(0.15, 0.2, 0.4)
	var flag_mat = _mat(flag_col, 0.95)
	var flag_mat_dark = _mat(Color(flag_col.r * 0.7, flag_col.g * 0.7, flag_col.b * 0.7), 0.95)
	var rot = randf() * TAU
	var fnode = Node3D.new()
	fnode.position = Vector3(0, 3.8, 0)
	fnode.rotation.y = rot
	for y in range(3):
		for x in range(4):
			var m = flag_mat if (x + y) % 2 == 0 else flag_mat_dark
			_cube(fnode, Vector3(0.25 + x * 0.3, -y * 0.3, 0), Vector3(0.3, 0.3, 0.04), m)
	# Emblem
	_cube(fnode, Vector3(0.75, -0.3, 0.03), Vector3(0.3, 0.3, 0.02), _mat(COL_GOLD, 0.4, 0.5))
	b.add_child(fnode)
	# Finial
	_cube(b, Vector3(0, 4.8, 0), Vector3(0.2, 0.2, 0.2), _mat(COL_GOLD, 0.3, 0.7))
	# Collision (pole only, flag reste traversable)
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(0.25, 4.5, 0.25)
	coll.shape = cs
	coll.position.y = 2.25
	body.add_child(coll)
	b.add_child(body)
	add_child(b)

func _voxel_campfire(p: Vector3):
	var f = Node3D.new()
	f.position = p
	# Stones circle
	for i in range(6):
		var a = i * TAU / 6.0
		_cube(f, Vector3(cos(a) * 0.6, 0.15, sin(a) * 0.6), Vector3(0.3, 0.3, 0.3), _mat(COL_STONE_DARK, 0.95))
	# Logs crossed
	_cube(f, Vector3(0, 0.2, 0), Vector3(0.7, 0.2, 0.15), _mat(COL_WOOD_DARK, 0.95))
	_cube(f, Vector3(0, 0.3, 0), Vector3(0.15, 0.2, 0.7), _mat(COL_WOOD_DARK, 0.95))
	# Embers
	_cube(f, Vector3(0, 0.45, 0), Vector3(0.35, 0.15, 0.35), _emissive_mat(Color(0.9, 0.3, 0.08), Color(0.9, 0.3, 0.05), 3.0))
	# Flames (traversables)
	_cube(f, Vector3(0, 0.65, 0), Vector3(0.3, 0.3, 0.3), _emissive_mat(Color(1.0, 0.5, 0.1), Color(1.0, 0.45, 0.08), 2.8))
	_cube(f, Vector3(0.05, 0.9, -0.02), Vector3(0.2, 0.25, 0.2), _emissive_mat(Color(1.0, 0.7, 0.2), Color(1.0, 0.6, 0.15), 2.5))
	# Light
	var lt = OmniLight3D.new()
	lt.light_color = Color(1.0, 0.55, 0.2)
	lt.light_energy = 1.8
	lt.omni_range = 7.0
	lt.position.y = 1.0
	f.add_child(lt)
	# Collision (cercle pierres, basse pour pas bloquer)
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = CylinderShape3D.new()
	cs.radius = 0.9
	cs.height = 0.4
	coll.shape = cs
	coll.position.y = 0.2
	body.add_child(coll)
	f.add_child(body)
	add_child(f)

func _voxel_torch(p: Vector3):
	var t = Node3D.new()
	t.position = p
	# Pole
	for i in range(3):
		_cube(t, Vector3(0, 0.3 + i * 0.5, 0), Vector3(0.12, 0.5, 0.12), _mat(COL_WOOD_DARK))
	# Fire
	var flame = _cube(t, Vector3(0, 1.75, 0), Vector3(0.25, 0.3, 0.25),
		_emissive_mat(Color(1.0, 0.5, 0.1), Color(1.0, 0.45, 0.08), 3.0))
	_cube(t, Vector3(0, 2.0, 0), Vector3(0.18, 0.2, 0.18),
		_emissive_mat(Color(1.0, 0.75, 0.3), Color(1.0, 0.65, 0.2), 2.5))
	# Light
	var lt = OmniLight3D.new()
	lt.light_color = Color(1.0, 0.55, 0.2)
	lt.light_energy = 1.2
	lt.omni_range = 5.0
	lt.position.y = 1.8
	t.add_child(lt)
	# Collision (pole only)
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(0.2, 1.5, 0.2)
	coll.shape = cs
	coll.position.y = 0.75
	body.add_child(coll)
	t.add_child(body)
	add_child(t)
	torches.append(flame)

func _voxel_shield(p: Vector3):
	var s = Node3D.new()
	s.position = p + Vector3(0, 0.05, 0)
	s.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
	var col = COL_CLOTH_RED if randf() > 0.5 else Color(0.15, 0.2, 0.4)
	# Main shield
	_cube(s, Vector3.ZERO, Vector3(0.5, 0.08, 0.65), _mat(col, 0.7))
	# Metal rim
	_cube(s, Vector3(0, -0.02, 0), Vector3(0.6, 0.05, 0.72), _mat(COL_METAL, 0.4, 0.6))
	# Boss
	_cube(s, Vector3(0, 0.06, 0), Vector3(0.15, 0.04, 0.15), _mat(COL_GOLD, 0.4, 0.6))
	# Collision (basse — franchissable mais plante les flèches)
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(0.6, 0.15, 0.72)
	coll.shape = cs
	body.add_child(coll)
	s.add_child(body)
	add_child(s)

func _voxel_helmet(p: Vector3):
	var h = Node3D.new()
	h.position = p + Vector3(0, 0.15, 0)
	h.rotation = Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5))
	_cube(h, Vector3.ZERO, Vector3(0.35, 0.3, 0.35), _mat(COL_METAL, 0.3, 0.8))
	_cube(h, Vector3(0, -0.1, 0.12), Vector3(0.3, 0.1, 0.12), _mat(COL_METAL, 0.3, 0.8))
	# Collision
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(0.4, 0.35, 0.4)
	coll.shape = cs
	body.add_child(coll)
	h.add_child(body)
	add_child(h)

func _voxel_sword(p: Vector3):
	var s = Node3D.new()
	s.position = p + Vector3(0, 0.05, 0)
	s.rotation = Vector3(PI / 2, randf() * TAU, randf_range(-0.2, 0.2))
	# Blade
	_cube(s, Vector3(0, 0.3, 0), Vector3(0.08, 0.6, 0.02), _mat(Color(0.55, 0.55, 0.58), 0.3, 0.85))
	# Guard
	_cube(s, Vector3(0, 0, 0), Vector3(0.25, 0.05, 0.06), _mat(COL_METAL, 0.4, 0.6))
	# Handle
	_cube(s, Vector3(0, -0.1, 0), Vector3(0.06, 0.18, 0.06), _mat(COL_WOOD_DARK))
	# Pommel
	_cube(s, Vector3(0, -0.22, 0), Vector3(0.09, 0.08, 0.09), _mat(COL_GOLD, 0.4, 0.5))
	# Collision (couché au sol)
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(0.25, 0.1, 1.0)
	coll.shape = cs
	body.add_child(coll)
	s.add_child(body)
	add_child(s)

func _voxel_arrow(p: Vector3):
	var a = Node3D.new()
	a.position = p
	a.rotation = Vector3(randf_range(0.7, 1.2), randf() * TAU, randf_range(-0.3, 0.3))
	# Shaft
	_cube(a, Vector3(0, 0.35, 0), Vector3(0.04, 0.7, 0.04), _mat(COL_WOOD))
	# Fletching
	_cube(a, Vector3(0, 0.65, 0), Vector3(0.15, 0.12, 0.02), _mat(Color(0.7, 0.7, 0.65)))
	_cube(a, Vector3(0, 0.65, 0), Vector3(0.02, 0.12, 0.15), _mat(Color(0.7, 0.7, 0.65)))
	# Collision
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(0.15, 0.8, 0.15)
	coll.shape = cs
	coll.position.y = 0.35
	body.add_child(coll)
	a.add_child(body)
	add_child(a)

func _voxel_corpse(p: Vector3):
	var c = Node3D.new()
	c.position = p
	c.rotation.y = randf() * TAU
	# Body
	_cube(c, Vector3(0, 0.15, 0), Vector3(0.6, 0.3, 0.4), _mat(Color(0.2, 0.15, 0.1)))
	# Armor plate
	_cube(c, Vector3(0, 0.2, 0), Vector3(0.62, 0.2, 0.42), _mat(COL_METAL, 0.4, 0.6))
	# Head
	_cube(c, Vector3(0.5, 0.2, 0), Vector3(0.3, 0.3, 0.3), _mat(COL_METAL, 0.3, 0.7))
	# Arms
	_cube(c, Vector3(0.1, 0.15, 0.35), Vector3(0.2, 0.2, 0.45), _mat(Color(0.18, 0.12, 0.08)))
	_cube(c, Vector3(-0.3, 0.15, -0.3), Vector3(0.2, 0.2, 0.35), _mat(Color(0.18, 0.12, 0.08)))
	# Blood patch (traversable)
	_cube(c, Vector3(0.2, 0.02, 0.2), Vector3(0.8, 0.01, 0.8), _mat(COL_BLOOD, 0.98))
	# Collision (basse, on peut passer par-dessus)
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(1.0, 0.4, 0.8)
	coll.shape = cs
	coll.position.y = 0.2
	body.add_child(coll)
	c.add_child(body)
	add_child(c)

func _voxel_barrel(p: Vector3):
	var b = Node3D.new()
	b.position = p
	# Stack of cubes for cylindrical look
	_cube(b, Vector3(0, 0.15, 0), Vector3(0.75, 0.3, 0.75), _mat(COL_WOOD))
	_cube(b, Vector3(0, 0.5, 0), Vector3(0.8, 0.3, 0.8), _mat(COL_WOOD_DARK))
	_cube(b, Vector3(0, 0.85, 0), Vector3(0.75, 0.3, 0.75), _mat(COL_WOOD))
	# Metal bands
	_cube(b, Vector3(0, 0.3, 0), Vector3(0.82, 0.07, 0.82), _mat(COL_METAL, 0.4, 0.7))
	_cube(b, Vector3(0, 0.7, 0), Vector3(0.82, 0.07, 0.82), _mat(COL_METAL, 0.4, 0.7))
	# Collision
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(0.8, 1.0, 0.8)
	coll.shape = cs
	coll.position.y = 0.5
	body.add_child(coll)
	b.add_child(body)
	add_child(b)

func _voxel_crate(p: Vector3):
	var c = Node3D.new()
	c.position = p
	c.rotation.y = randf() * TAU
	_cube(c, Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.8), _mat(COL_WOOD))
	# Planks detail
	for i in range(3):
		_cube(c, Vector3(0, 0.2 + i * 0.3, 0.41), Vector3(0.78, 0.02, 0.01), _mat(COL_WOOD_DARK))
		_cube(c, Vector3(0, 0.2 + i * 0.3, -0.41), Vector3(0.78, 0.02, 0.01), _mat(COL_WOOD_DARK))
	# Collision
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = BoxShape3D.new()
	cs.size = Vector3(0.8, 0.8, 0.8)
	coll.shape = cs
	coll.position.y = 0.4
	body.add_child(coll)
	c.add_child(body)
	add_child(c)

func _voxel_stake(p: Vector3):
	var s = Node3D.new()
	s.position = p
	s.rotation = Vector3(randf_range(-0.25, 0.25), randf() * TAU, randf_range(-0.25, 0.25))
	for i in range(3):
		var sz_top = 0.25 - i * 0.06
		_cube(s, Vector3(0, 0.2 + i * 0.4, 0), Vector3(sz_top, 0.4, sz_top), _mat(COL_WOOD_DARK))
	# Collision (pieu entier)
	var body = StaticBody3D.new()
	var coll = CollisionShape3D.new()
	var cs = CylinderShape3D.new()
	cs.radius = 0.15
	cs.height = 1.2
	coll.shape = cs
	coll.position.y = 0.6
	body.add_child(coll)
	s.add_child(body)
	add_child(s)

func spawn_player():
	player = preload("res://player.tscn").instantiate()
	player.position = Vector3(MW/4*TS, 2.0, MH/2*TS)
	add_child(player)

func spawn_hud():
	var h = preload("res://hud.tscn").instantiate()
	add_child(h)

func start_wave():
	wave += 1
	for i in range(3 + wave * 2):
		var e = preload("res://enemy.tscn").instantiate()
		e.position = Vector3((MW-8)*TS, 1.0, randi_range(2, MH-2)*TS)
		add_child(e)
		enemies.append(e)

func _process(d):
	if not game_running: return
	enemies = enemies.filter(func(e): return is_instance_valid(e))
	if enemies.size() == 0: start_wave()
	# Flicker torches
	var t = Time.get_ticks_msec() / 1000.0
	for f in torches:
		if is_instance_valid(f):
			var flick = sin(t * 15.0 + f.position.x * 10.0) * 0.03 + cos(t * 22.0) * 0.02
			f.scale = Vector3.ONE * (1.0 + flick)
