# ============================================
# weapon_inventory.gd — Inventaire d'armes équipées
# ============================================
# Node attaché au Player. Gère la liste d'armes équipées + l'arme active.
# Actuellement 1 seule arme (arbalète), mais prêt à en accueillir plusieurs.
#
# FONCTIONS PRINCIPALES :
#   add_weapon(weapon)    → Ajouter une arme à l'inventaire
#   equip(index)          → Équiper l'arme du slot (devient arme active)
#   switch_next()         → Passer à l'arme suivante (pour le bouton switch futur)
#   get_current()         → Retourne la WeaponData de l'arme active
#
# DANS LA PROCHAINE SESSION, on ajoutera juste :
#   var sword = load("res://weapons/sword.tres")
#   inventory.add_weapon(sword)
# Et le joueur aura 2 armes switchables. Aucun refactor.
# ============================================

extends Node

# Liste des armes équipées (slots). Index 0 = arme principale par défaut.
var weapons: Array[WeaponData] = []

# Index de l'arme actuellement active dans le tableau weapons
var current_index: int = 0

# Référence au WeaponController (sibling node). Résolue à la demande pour éviter
# les problèmes de timing @onready si add_weapon() est appelé juste après add_child.
var controller: Node = null

func _get_controller() -> Node:
	if controller == null or not is_instance_valid(controller):
		var parent = get_parent()
		if parent != null:
			controller = parent.get_node_or_null("WeaponController")
	return controller

# ====== API PUBLIQUE ======

# Ajouter une arme à l'inventaire. Si c'est la première, elle est équipée auto.
func add_weapon(weapon: WeaponData) -> void:
	if weapon == null:
		return
	weapons.append(weapon)
	# Première arme ajoutée → équiper automatiquement
	if weapons.size() == 1:
		equip(0)

# Équiper l'arme du slot donné
func equip(index: int) -> void:
	if index < 0 or index >= weapons.size():
		push_warning("WeaponInventory: index invalide: %d (taille: %d)" % [index, weapons.size()])
		return
	current_index = index
	var c = _get_controller()
	if c != null:
		c.set_weapon(weapons[index])

# Passer à l'arme suivante (pour bouton switch — pas utilisé cette session)
func switch_next() -> void:
	if weapons.size() <= 1:
		return
	var next: int = (current_index + 1) % weapons.size()
	equip(next)

# Retourne l'arme active (ou null si inventaire vide)
func get_current() -> WeaponData:
	if weapons.size() == 0:
		return null
	return weapons[current_index]
