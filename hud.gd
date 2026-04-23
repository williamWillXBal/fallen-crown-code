# ============================================
# HUD.GD — Interface mobile (joysticks, boutons, crosshair, vignette dégâts, settings)
# ============================================
# FONCTIONS (cherche par Ctrl+F sur le nom) :
#   _ready()                → Crée tous les éléments HUD (joysticks, boutons, viseur, settings)
#   _process(_d)            → Update continu (HP bar, kills, vignette, flash)
#   show_dmg_flash()        → Déclenche flash rouge quand joueur touché
#   _input(event)           → Gère clic bouton attaque, saut, settings
#   _toggle_settings()      → Ouvre/ferme le panneau de settings
#   _build_settings_panel() → Construit le contenu du panneau (extensible)
#   _add_section(titre)     → Helper : ajoute une section visuelle dans le panneau
#   _add_slider(...)        → Helper : ajoute un slider (label, clé Settings, min, max, step)
#   _add_checkbox(...)      → Helper : ajoute une checkbox (label, clé Settings)
#
# CONSTANTES / REFS IMPORTANTES :
#   joy_base / joy_thumb          → Joystick gauche (déplacement)
#   look_base / look_thumb        → Joystick droit (caméra)
#   atk_btn (rayon 55)            → Bouton attaque rouge
#   jump_btn (rayon 50)           → Bouton saut bleu
#   crosshair                     → Viseur central croix + point
#   hit_marker                    → 4 branches blanches quand hit (style COD)
#   hit_timer                     → Durée restante affichage hit marker
#   hp_bar / hp_lbl               → Barre et texte HP en haut gauche
#   inv_lbl                       → Affichage ressources (Bois/Pierre/Fer/Or)
#   wave_lbl                      → Affichage wave/kills
#   craft_prompt                  → Prompt "Craft" quand près d'une table (vert/rouge)
#   dmg_vignette / dmg_flash      → Vignette rouge bords quand touché
#   low_hp_pulse                  → Pulse rouge quand HP ≤ 30
#   settings_btn                  → Bouton ⚙ en haut à droite
#   settings_panel                → Panneau overlay avec sliders/checkboxes
#   settings_content_vbox         → VBoxContainer où on ajoute les options
#   settings_open (bool)          → État ouvert/fermé du panneau
#
# POUR AJOUTER UNE OPTION AU MENU SETTINGS :
#   1. Ajoute la clé dans Settings.DEFAULTS (settings.gd)
#   2. Dans _build_settings_panel(), appelle _add_slider(...) ou _add_checkbox(...)
#   3. Dans le code qui consomme la valeur : Settings.get_value("cle", default)
# ============================================

extends CanvasLayer

var joy_base: Control
var joy_thumb: Control
var joy_center := Vector2(180, 600)
var joy_radius := 70.0

var look_base: Control
var look_thumb: Control
var look_center := Vector2(800, 600)
var look_radius := 70.0

var atk_btn: Control
var atk_center := Vector2(0, 0)
var atk_radius := 55.0
var atk_pressed := false

var jump_btn: Control
var jump_center := Vector2(0, 0)
var jump_radius := 50.0
var crosshair: Control
var hit_marker: Control
var hit_timer := 0.0
var hp_bar: ProgressBar
var hp_lbl: Label
var inv_lbl: Label
var wave_lbl: Label
var craft_prompt: Label  # Prompt "Craft" quand près d'une table (centré bas)
# Damage vignette
var dmg_vignette: Control
var dmg_flash := 0.0
var low_hp_pulse := 0.0

# Settings (bouton ⚙ en haut à droite + panneau overlay)
var settings_btn: Control
var settings_center := Vector2(0, 0)
var settings_radius := 28.0
var settings_panel: Control
var settings_content_vbox: VBoxContainer
var settings_open := false

func _ready():
	# Le HUD doit continuer à tourner même quand le jeu est en pause (menu settings)
	process_mode = Node.PROCESS_MODE_ALWAYS
	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(20, 20)
	hp_bar.size = Vector2(250, 25)
	hp_bar.value = 100
	hp_bar.show_percentage = false
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.8, 0.15, 0.1)
	hp_bar.add_theme_stylebox_override("fill", bs)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.1)
	hp_bar.add_theme_stylebox_override("background", bg)
	add_child(hp_bar)

	hp_lbl = Label.new()
	hp_lbl.position = Vector2(25, 22)
	hp_lbl.text = "HP 100"
	hp_lbl.add_theme_font_size_override("font_size", 14)
	add_child(hp_lbl)

	inv_lbl = Label.new()
	inv_lbl.position = Vector2(20, 55)
	inv_lbl.text = "Bois:0  Pierre:0  Fer:0  Or:0"
	inv_lbl.add_theme_font_size_override("font_size", 16)
	inv_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	add_child(inv_lbl)

	wave_lbl = Label.new()
	wave_lbl.position = Vector2(20, 85)
	wave_lbl.text = "WAVE 1"
	wave_lbl.add_theme_font_size_override("font_size", 12)
	add_child(wave_lbl)

	# Prompt "Craft" : Label centré en bas (au-dessus du HUD bottom), invisible
	# par défaut. Se montre quand le player est près d'une table de craft.
	# Couleur verte si débloqué, orange/rouge si verrouillé.
	craft_prompt = Label.new()
	craft_prompt.text = ""
	craft_prompt.add_theme_font_size_override("font_size", 22)
	craft_prompt.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	craft_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	craft_prompt.add_theme_constant_override("outline_size", 4)
	craft_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	craft_prompt.anchor_left = 0.0
	craft_prompt.anchor_right = 1.0
	craft_prompt.anchor_top = 0.55
	craft_prompt.anchor_bottom = 0.55
	craft_prompt.visible = false
	add_child(craft_prompt)

	var vp = get_viewport().get_visible_rect().size
	joy_center = Vector2(180, vp.y - 180)
	look_center = Vector2(vp.x - 180, vp.y - 180)
	atk_center = Vector2(vp.x - 180, vp.y - 360)
	jump_center = Vector2(vp.x - 320, vp.y - 240)

	joy_base = Control.new()
	add_child(joy_base)
	joy_base.draw.connect(func():
		joy_base.draw_circle(joy_center, joy_radius, Color(1, 1, 1, 0.15))
		joy_base.draw_arc(joy_center, joy_radius, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	)
	joy_thumb = Control.new()
	add_child(joy_thumb)
	joy_thumb.draw.connect(func():
		var pl = get_parent().player
		var offset = Vector2.ZERO
		if pl and pl.move_tid >= 0:
			offset = pl.move_vec * (joy_radius * 0.6)
		joy_thumb.draw_circle(joy_center + offset, 28, Color(1, 1, 1, 0.45))
	)

	look_base = Control.new()
	add_child(look_base)
	look_base.draw.connect(func():
		look_base.draw_circle(look_center, look_radius, Color(1, 1, 1, 0.15))
		look_base.draw_arc(look_center, look_radius, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	)
	look_thumb = Control.new()
	add_child(look_thumb)
	look_thumb.draw.connect(func():
		var pl = get_parent().player
		var active = pl and pl.look_tid >= 0
		var color = Color(1, 1, 1, 0.55) if active else Color(1, 1, 1, 0.25)
		look_thumb.draw_circle(look_center, 28, color)
	)

	atk_btn = Control.new()
	add_child(atk_btn)
	atk_btn.draw.connect(func():
		var col = Color(0.9, 0.3, 0.2, 0.7) if atk_pressed else Color(0.9, 0.3, 0.2, 0.4)
		atk_btn.draw_circle(atk_center, atk_radius, col)
		atk_btn.draw_arc(atk_center, atk_radius, 0, TAU, 48, Color(1, 1, 1, 0.6), 2.0)
	)

	jump_btn = Control.new()
	add_child(jump_btn)
	jump_btn.draw.connect(func():
		jump_btn.draw_circle(jump_center, jump_radius, Color(0.3, 0.6, 0.9, 0.4))
		jump_btn.draw_arc(jump_center, jump_radius, 0, TAU, 48, Color(1, 1, 1, 0.6), 2.0)
	)

	# Crosshair
	crosshair = Control.new()
	add_child(crosshair)
	crosshair.draw.connect(func():
		var c = get_viewport().get_visible_rect().size / 2
		crosshair.draw_line(c + Vector2(-10, 0), c + Vector2(-3, 0), Color(1, 1, 1, 0.8), 2)
		crosshair.draw_line(c + Vector2(3, 0), c + Vector2(10, 0), Color(1, 1, 1, 0.8), 2)
		crosshair.draw_line(c + Vector2(0, -10), c + Vector2(0, -3), Color(1, 1, 1, 0.8), 2)
		crosshair.draw_line(c + Vector2(0, 3), c + Vector2(0, 10), Color(1, 1, 1, 0.8), 2)
		crosshair.draw_circle(c, 1.5, Color(1, 1, 1, 0.9))
	)

	# Hit marker — style Polygon Arena / COD
	hit_marker = Control.new()
	add_child(hit_marker)
	hit_marker.draw.connect(func():
		if hit_timer > 0:
			var c = get_viewport().get_visible_rect().size / 2
			var a = clamp(hit_timer / 0.15, 0.0, 1.0)
			var col = Color(1, 1, 1, a)
			var gap = 5.0
			var len = 14.0
			# Top-left branch
			hit_marker.draw_line(c + Vector2(-gap, -gap), c + Vector2(-len, -len), col, 2.5)
			# Top-right branch
			hit_marker.draw_line(c + Vector2(gap, -gap), c + Vector2(len, -len), col, 2.5)
			# Bottom-left branch
			hit_marker.draw_line(c + Vector2(-gap, gap), c + Vector2(-len, len), col, 2.5)
			# Bottom-right branch
			hit_marker.draw_line(c + Vector2(gap, gap), c + Vector2(len, len), col, 2.5)
	)

	# Damage vignette — red edges when hit + pulse when low HP
	dmg_vignette = Control.new()
	dmg_vignette.z_index = 10
	add_child(dmg_vignette)
	dmg_vignette.draw.connect(func():
		var vps = get_viewport().get_visible_rect().size
		var pl = get_parent().player if get_parent() else null
		var alpha := 0.0
		# Flash on hit
		if dmg_flash > 0:
			alpha = clamp(dmg_flash / 0.3, 0.0, 0.4)
		# Low HP pulse — urgence extreme under 30 HP
		if pl and pl.hp <= 30 and pl.hp > 0:
			var pulse = (sin(low_hp_pulse * 6.0) + 1.0) / 2.0
			var intensity = lerp(0.15, 0.5, pulse)
			if pl.hp <= 15:
				intensity = lerp(0.3, 0.7, pulse)
			alpha = max(alpha, intensity)
		if alpha > 0.01:
			var col = Color(0.8, 0.05, 0.0, alpha)
			var w = 80.0
			# Top edge
			dmg_vignette.draw_rect(Rect2(0, 0, vps.x, w), Color(col.r, col.g, col.b, col.a * 0.7))
			# Bottom edge
			dmg_vignette.draw_rect(Rect2(0, vps.y - w, vps.x, w), Color(col.r, col.g, col.b, col.a * 0.7))
			# Left edge
			dmg_vignette.draw_rect(Rect2(0, 0, w, vps.y), Color(col.r, col.g, col.b, col.a * 0.5))
			# Right edge
			dmg_vignette.draw_rect(Rect2(vps.x - w, 0, w, vps.y), Color(col.r, col.g, col.b, col.a * 0.5))
	)

	# Settings button (⚙ haut droite)
	settings_center = Vector2(vp.x - 50, 50)
	settings_btn = Control.new()
	settings_btn.z_index = 20
	add_child(settings_btn)
	settings_btn.draw.connect(func():
		settings_btn.draw_circle(settings_center, settings_radius, Color(0.1, 0.1, 0.12, 0.7))
		settings_btn.draw_arc(settings_center, settings_radius, 0, TAU, 32, Color(0.83, 0.66, 0.32, 0.9), 2.0)
	)
	var cog_lbl := Label.new()
	cog_lbl.text = "⚙"
	cog_lbl.add_theme_font_size_override("font_size", 28)
	cog_lbl.add_theme_color_override("font_color", Color(0.83, 0.66, 0.32))
	cog_lbl.position = Vector2(settings_center.x - 14, settings_center.y - 22)
	cog_lbl.z_index = 21
	add_child(cog_lbl)

	# Settings panel (overlay, caché par défaut)
	settings_panel = Control.new()
	settings_panel.visible = false
	settings_panel.z_index = 50
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(settings_panel)

	# Fond semi-transparent sur tout l'écran
	var bg_panel := ColorRect.new()
	bg_panel.color = Color(0, 0, 0, 0.7)
	bg_panel.size = vp
	bg_panel.position = Vector2.ZERO
	settings_panel.add_child(bg_panel)

	# Conteneur central du panneau
	# Note : typés explicitement en float car min() retourne Variant (Godot ne peut pas
	# inférer depuis min() qui accepte plusieurs types → erreur "inferred from Variant")
	var panel_w: float = min(vp.x * 0.85, 520.0)
	var panel_h: float = min(vp.y * 0.8, 700.0)
	var panel_bg := ColorRect.new()
	panel_bg.color = Color(0.08, 0.08, 0.1, 0.98)
	panel_bg.size = Vector2(panel_w, panel_h)
	panel_bg.position = Vector2((vp.x - panel_w) / 2, (vp.y - panel_h) / 2)
	settings_panel.add_child(panel_bg)

	# Bordure dorée
	var border := Control.new()
	border.z_index = 1
	panel_bg.add_child(border)
	border.draw.connect(func():
		border.draw_rect(Rect2(Vector2.ZERO, Vector2(panel_w, panel_h)), Color(0.83, 0.66, 0.32, 0.8), false, 2.0)
	)

	# Titre
	var title := Label.new()
	title.text = "⚙  RÉGLAGES"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.83, 0.66, 0.32))
	title.position = Vector2(24, 18)
	panel_bg.add_child(title)

	# Bouton X (fermer) en haut à droite du panneau
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.size = Vector2(48, 48)
	close_btn.position = Vector2(panel_w - 60, 12)
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	close_btn.pressed.connect(_toggle_settings)
	panel_bg.add_child(close_btn)

	# ScrollContainer + VBox pour les options (scroll si beaucoup d'options)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 70)
	scroll.size = Vector2(panel_w - 40, panel_h - 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_bg.add_child(scroll)

	settings_content_vbox = VBoxContainer.new()
	settings_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_content_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(settings_content_vbox)

	# Bouton Reset tout en bas
	var reset_btn := Button.new()
	reset_btn.text = "Réinitialiser par défaut"
	reset_btn.size = Vector2(panel_w - 40, 44)
	reset_btn.position = Vector2(20, panel_h - 64)
	reset_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
	reset_btn.pressed.connect(func():
		Settings.reset()
		# Reconstruit le panneau pour refléter les nouvelles valeurs
		for c in settings_content_vbox.get_children():
			c.queue_free()
		_build_settings_panel()
	)
	panel_bg.add_child(reset_btn)

	# Construit le contenu du panneau (sections + options)
	_build_settings_panel()

func _process(_d):
	var main = get_parent()
	if main and main.player:
		var p = main.player
		hp_bar.value = (float(p.hp) / p.max_hp) * 100
		hp_lbl.text = "HP " + str(p.hp)
		inv_lbl.text = "Bois:" + str(p.inventory.wood) + "  Pierre:" + str(p.inventory.stone) + "  Fer:" + str(p.inventory.iron) + "  Or:" + str(p.inventory.gold)
		wave_lbl.text = "WAVE " + str(main.wave) + " | KILLS " + str(p.kills)
	if joy_thumb:
		joy_thumb.queue_redraw()
	if look_thumb:
		look_thumb.queue_redraw()
	if atk_btn:
		atk_btn.queue_redraw()
	if hit_timer > 0:
		hit_timer -= _d
	if hit_marker:
		hit_marker.queue_redraw()
	# Damage vignette updates
	if dmg_flash > 0:
		dmg_flash -= _d
	low_hp_pulse += _d
	if dmg_vignette:
		dmg_vignette.queue_redraw()

func show_dmg_flash():
	dmg_flash = 0.3

# Affiche ou masque le prompt "Craft" selon la proximité d'une table.
# Appelé par player.gd à chaque frame.
# - text : texte à afficher (ex: "🔨 Forge", "🔒 5 kills requis")
# - is_unlocked : true = vert (débloqué), false = orange (verrouillé)
# - Si text est vide, le prompt est masqué.
func show_craft_prompt(text: String, is_unlocked: bool):
	if text == "":
		craft_prompt.visible = false
		return
	craft_prompt.text = text
	craft_prompt.visible = true
	if is_unlocked:
		craft_prompt.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))  # Vert
	else:
		craft_prompt.add_theme_color_override("font_color", Color(1.0, 0.55, 0.25))  # Orange

func _input(event):
	if event is InputEventScreenTouch:
		# Si le panneau settings est ouvert, on laisse passer (les Controls internes gèrent)
		if settings_open:
			return
		# Priorité : bouton settings en haut à droite
		var set_dist = event.position.distance_to(settings_center)
		if event.pressed and set_dist <= settings_radius:
			_toggle_settings()
			return
		var atk_dist = event.position.distance_to(atk_center)
		var jump_dist = event.position.distance_to(jump_center)
		if event.pressed and atk_dist <= atk_radius:
			atk_pressed = true
			var pl = get_parent().player
			if pl:
				if pl.has_xbow: pl.do_shoot()
				else: pl.do_atk()
		elif event.pressed and jump_dist <= jump_radius:
			var pl = get_parent().player
			if pl and pl.is_on_floor():
				pl.velocity.y = 7.0
		elif not event.pressed:
			atk_pressed = false

# ============================================
# SETTINGS — ouverture/fermeture + construction extensible du panneau
# ============================================

func _toggle_settings() -> void:
	settings_open = not settings_open
	settings_panel.visible = settings_open
	# Met le jeu en pause quand le menu est ouvert (facultatif mais propre)
	get_tree().paused = settings_open

func _build_settings_panel() -> void:
	# ⬇️  TOUTES LES OPTIONS DU MENU SONT ICI. Pour en ajouter, appelle un helper.
	_add_section("Caméra")
	_add_slider("Sensibilité horizontale", "cam_sens_h", 0.001, 0.02, 0.0005)
	_add_slider("Sensibilité verticale",   "cam_sens_v", 0.001, 0.02, 0.0005)
	# Exemples pour plus tard (décommente quand tu as ajouté la clé dans Settings.DEFAULTS) :
	# _add_checkbox("Inverser l'axe Y", "cam_invert_y")
	# _add_slider("Champ de vision (FOV)", "cam_fov", 60.0, 110.0, 1.0)
	#
	# _add_section("Son")
	# _add_slider("Volume effets", "vol_sfx", 0.0, 1.0, 0.05)
	# _add_slider("Volume musique", "vol_music", 0.0, 1.0, 0.05)
	#
	# _add_section("Gameplay")
	# _add_checkbox("Vibrations", "haptic_feedback")

func _add_section(title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	settings_content_vbox.add_child(spacer)
	var lbl := Label.new()
	lbl.text = "▸ " + title.to_upper()
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.83, 0.66, 0.32))
	settings_content_vbox.add_child(lbl)
	var sep := ColorRect.new()
	sep.color = Color(0.83, 0.66, 0.32, 0.25)
	sep.custom_minimum_size = Vector2(0, 1)
	settings_content_vbox.add_child(sep)

func _add_slider(label_text: String, key: String, min_value: float, max_value: float, step: float) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	settings_content_vbox.add_child(row)

	# Header : label + valeur actuelle
	var header := HBoxContainer.new()
	row.add_child(header)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(lbl)
	var val_lbl := Label.new()
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", Color(0.83, 0.66, 0.32))
	header.add_child(val_lbl)

	# Slider
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(0, 28)
	var current: float = Settings.get_value(key, min_value)
	slider.value = current
	val_lbl.text = "%.4f" % current
	slider.value_changed.connect(func(v: float):
		Settings.set_value(key, v)
		val_lbl.text = "%.4f" % v
	)
	row.add_child(slider)

func _add_checkbox(label_text: String, key: String) -> void:
	var cb := CheckBox.new()
	cb.text = "  " + label_text
	cb.add_theme_font_size_override("font_size", 15)
	cb.button_pressed = Settings.get_value(key, false)
	cb.toggled.connect(func(pressed: bool):
		Settings.set_value(key, pressed)
	)
	settings_content_vbox.add_child(cb)
