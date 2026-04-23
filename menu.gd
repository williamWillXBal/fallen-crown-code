extends Control
# ============================================
# MENU.GD — Menu principal du jeu
# ============================================
# Affiche l'écran titre avec 4 choix : JOUER / OPTIONS / CRÉDITS / QUITTER.
# Clic JOUER → change_scene_to_file vers main.tscn (jeu actuel avec IA de test).
# Ambiance voxel sombre cohérente avec le reste du jeu (fond noir, titre doré
# émissif-like, boutons larges pour le tactile mobile).
#
# Vision : 100% multijoueur à terme. L'IA actuelle reste comme mode "dev/test"
# qui deviendra un mode "Entraînement" plus tard. Le menu lance pour l'instant
# directement la scène main.tscn.
#
# FONCTIONS (cherche par Ctrl+F sur le nom) :
#   _ready()                → Construit les 3 panneaux (titre / options / crédits)
#   _build_title()          → Écran d'accueil : logo + 4 boutons
#   _build_options()        → Écran options (placeholder pour l'instant)
#   _build_credits()        → Écran crédits (William + Claude + audio)
#   _show_panel(name)       → Affiche un panneau et cache les autres
#   _make_button(text, cb)  → Helper : crée un bouton stylé tactile
#   _on_play()              → Lance main.tscn
#   _on_options()           → Affiche le panneau options
#   _on_credits()           → Affiche le panneau crédits
#   _on_quit()              → Quitte le jeu
#   _on_back()              → Retour au titre

var title_panel: Control
var options_panel: Control
var credits_panel: Control

# Couleurs de thème (cohérent avec le HUD existant)
const COL_BG := Color(0.08, 0.08, 0.1, 1.0)           # Fond presque noir
const COL_TITLE := Color(1.0, 0.82, 0.35)             # Doré titre
const COL_TITLE_OUTLINE := Color(0.3, 0.15, 0.0, 1.0) # Outline sombre
const COL_BTN_BG := Color(0.15, 0.15, 0.18, 0.9)      # Gris très foncé
const COL_BTN_HOVER := Color(0.25, 0.22, 0.15, 0.95)  # Brun foncé survol
const COL_BTN_TXT := Color(0.95, 0.88, 0.65)          # Beige clair
const COL_TEXT := Color(0.85, 0.78, 0.55)             # Texte secondaire

func _ready():
	# Fond noir plein écran
	var bg = ColorRect.new()
	bg.color = COL_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# Construction des 3 panneaux (un seul visible à la fois)
	title_panel = _build_title()
	options_panel = _build_options()
	credits_panel = _build_credits()
	add_child(title_panel)
	add_child(options_panel)
	add_child(credits_panel)
	_show_panel("title")

# Écran d'accueil : logo du jeu + 4 boutons principaux
func _build_title() -> Control:
	var panel = Control.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	# Titre "FALLEN CROWN" centré haut
	var title = Label.new()
	title.text = "FALLEN CROWN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.12
	title.anchor_bottom = 0.12
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", COL_TITLE)
	title.add_theme_color_override("font_outline_color", COL_TITLE_OUTLINE)
	title.add_theme_constant_override("outline_size", 6)
	panel.add_child(title)
	# Sous-titre
	var subtitle = Label.new()
	subtitle.text = "Battle Royale Voxel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0.0
	subtitle.anchor_right = 1.0
	subtitle.anchor_top = 0.22
	subtitle.anchor_bottom = 0.22
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", COL_TEXT)
	panel.add_child(subtitle)
	# Conteneur central pour les 4 boutons (VBoxContainer)
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.3
	vbox.anchor_right = 0.7
	vbox.anchor_top = 0.4
	vbox.anchor_bottom = 0.85
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	vbox.add_child(_make_button("JOUER", _on_play))
	vbox.add_child(_make_button("OPTIONS", _on_options))
	vbox.add_child(_make_button("CRÉDITS", _on_credits))
	vbox.add_child(_make_button("QUITTER", _on_quit))
	return panel

# Écran options : placeholder (les vrais settings sont dans le HUD en jeu pour l'instant)
func _build_options() -> Control:
	var panel = Control.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.visible = false
	var title = Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.1
	title.anchor_bottom = 0.1
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", COL_TITLE)
	panel.add_child(title)
	var info = Label.new()
	info.text = "Les réglages (sensibilité caméra, etc.) sont accessibles\nvia le bouton ⚙ en jeu.\n\nD'autres options seront ajoutées ici plus tard."
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.anchor_left = 0.1
	info.anchor_right = 0.9
	info.anchor_top = 0.3
	info.anchor_bottom = 0.6
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", COL_TEXT)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(info)
	# Bouton retour
	var back_box = VBoxContainer.new()
	back_box.anchor_left = 0.35
	back_box.anchor_right = 0.65
	back_box.anchor_top = 0.8
	back_box.anchor_bottom = 0.9
	panel.add_child(back_box)
	back_box.add_child(_make_button("RETOUR", _on_back))
	return panel

# Écran crédits
func _build_credits() -> Control:
	var panel = Control.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.visible = false
	var title = Label.new()
	title.text = "CRÉDITS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.1
	title.anchor_bottom = 0.1
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", COL_TITLE)
	panel.add_child(title)
	var content = Label.new()
	content.text = "Jeu créé par\nWILLIAM\n\nDéveloppement assisté par\nANTHROPIC CLAUDE\n\n— Audio —\nenemy_death.wav : theuncertainman (Freesound, CC-BY)\nhit_impact.wav : Ali_6868 (Freesound, CC0)\n\nMerci !"
	content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.anchor_left = 0.1
	content.anchor_right = 0.9
	content.anchor_top = 0.22
	content.anchor_bottom = 0.78
	content.add_theme_font_size_override("font_size", 18)
	content.add_theme_color_override("font_color", COL_TEXT)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(content)
	var back_box = VBoxContainer.new()
	back_box.anchor_left = 0.35
	back_box.anchor_right = 0.65
	back_box.anchor_top = 0.8
	back_box.anchor_bottom = 0.9
	panel.add_child(back_box)
	back_box.add_child(_make_button("RETOUR", _on_back))
	return panel

# Affiche un seul panneau (title / options / credits), cache les 2 autres
func _show_panel(name: String):
	title_panel.visible = (name == "title")
	options_panel.visible = (name == "options")
	credits_panel.visible = (name == "credits")

# Helper : crée un bouton stylé cohérent, taille adaptée au tactile
func _make_button(txt: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(260, 60)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", COL_BTN_TXT)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))
	b.add_theme_color_override("font_pressed_color", COL_TITLE)
	# StyleBox pour chaque état (normal / survol / pressé)
	var sb_normal = StyleBoxFlat.new()
	sb_normal.bg_color = COL_BTN_BG
	sb_normal.border_color = Color(0.35, 0.3, 0.2)
	sb_normal.border_width_left = 2
	sb_normal.border_width_right = 2
	sb_normal.border_width_top = 2
	sb_normal.border_width_bottom = 2
	sb_normal.corner_radius_top_left = 4
	sb_normal.corner_radius_top_right = 4
	sb_normal.corner_radius_bottom_left = 4
	sb_normal.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", sb_normal)
	var sb_hover = sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = COL_BTN_HOVER
	sb_hover.border_color = COL_TITLE
	b.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed = sb_normal.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = Color(0.4, 0.3, 0.15, 0.95)
	b.add_theme_stylebox_override("pressed", sb_pressed)
	b.pressed.connect(cb)
	return b

# Callbacks des boutons
func _on_play():
	get_tree().change_scene_to_file("res://main.tscn")

func _on_options():
	_show_panel("options")

func _on_credits():
	_show_panel("credits")

func _on_quit():
	get_tree().quit()

func _on_back():
	_show_panel("title")
