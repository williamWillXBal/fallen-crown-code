# ============================================
# weapon_controller.gd — Contrôleur générique d'arme
# ============================================
# Node attaché au Player. Sait utiliser N'IMPORTE QUELLE arme en lisant son
# WeaponData. Le player ne fait plus appeler do_shoot() / do_atk() directement
# à partir du HUD : tout passe par try_attack() ici.
#
# DISPATCH : selon le type d'arme (WeaponData.type), on appelle la bonne fonction
# du player (qui garde sa logique spécifique existante). C'est l'approche
# "wrap, don't replace" : ZÉRO régression sur le code qui marche.
#
# POUR AJOUTER UNE NOUVELLE ARME :
#   1. Ajouter le type dans WeaponData.WeaponType
#   2. Ajouter un case dans try_attack()
#   3. Créer la fonction correspondante dans player.gd (ou ici si générique)
# ============================================

extends Node

# Arme actuellement équipée (lue à chaque attaque)
var current_weapon: WeaponData = null

# Référence au player (parent). Résolue à la demande pour éviter problèmes @onready.
var player: CharacterBody3D = null

func _get_player() -> CharacterBody3D:
	if player == null or not is_instance_valid(player):
		var p = get_parent()
		if p is CharacterBody3D:
			player = p
	return player

# Timer de cooldown partagé. Lu par le HUD pour griser le bouton attaque si besoin.
var cd_timer: float = 0.0

# Munitions actuelles (si l'arme en utilise, sinon -1 = illimité)
var ammo_current: int = -1

# État reload (actuellement non utilisé — l'arbalète n'a pas de reload)
var is_reloading: bool = false

# ====== API PUBLIQUE ======

# Équiper une arme (appelé par WeaponInventory au démarrage + au switch)
func set_weapon(weapon: WeaponData) -> void:
	current_weapon = weapon
	if weapon == null:
		return
	# Reset des munitions au changement d'arme
	ammo_current = weapon.ammo_max
	# Reset du timer pour éviter un enchaînement abusif après switch
	cd_timer = 0.1
	# Charger le son de l'arme dans le player si besoin
	if weapon.sound_shoot != null:
		var p = _get_player()
		if p != null and p.has_method("set_weapon_sound"):
			p.set_weapon_sound(weapon.sound_shoot, weapon.sound_volume_db)
	# Activer le modèle 3D correspondant (cache les autres)
	var pl = _get_player()
	if pl != null and pl.has_method("show_weapon_model"):
		pl.show_weapon_model(weapon.id)

# Déclencher une attaque — appelé par le HUD (remplace les appels directs do_shoot/do_atk)
func try_attack() -> void:
	if current_weapon == null:
		return
	if cd_timer > 0.0:
		return
	if is_reloading:
		return
	# Dispatch selon le type d'arme
	match current_weapon.type:
		WeaponData.WeaponType.RANGED_CROSSBOW:
			_do_ranged_crossbow()
		WeaponData.WeaponType.MELEE_SWORD:
			_do_melee_sword()
		_:
			push_warning("WeaponController: type d'arme non géré: %s" % current_weapon.type)

# ====== DISPATCH INTERNE ======

# Arbalète : délègue à player.do_shoot() qui contient toute la logique existante
# (raycast, spawn_bolt, attach_point, ragdoll transfer, etc.) — approche "wrap".
func _do_ranged_crossbow() -> void:
	var p = _get_player()
	if p == null or not p.has_method("do_shoot"):
		return
	p.do_shoot()
	# Applique le cooldown DU WEAPONDATA (et non plus hardcodé xbow_cd)
	cd_timer = current_weapon.cooldown

# Épée : délègue à player.do_atk() — déjà existante dans le code
func _do_melee_sword() -> void:
	var p = _get_player()
	if p == null or not p.has_method("do_atk"):
		return
	p.do_atk()
	cd_timer = current_weapon.cooldown

# ====== BOUCLE ======

func _process(delta: float) -> void:
	if cd_timer > 0.0:
		cd_timer -= delta
