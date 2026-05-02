# ============================================
# weapon_data.gd — Définition de données d'une arme
# ============================================
# Classe Resource : chaque arme est un fichier .tres qui contient ses stats.
# Aucune logique ici, juste des valeurs. La logique est dans weapon_controller.gd.
#
# AVANTAGE : ajouter une nouvelle arme = créer un .tres avec les bonnes valeurs.
# Pas besoin de toucher au code. Scalable pour 1, 10 ou 100 armes.
#
# UTILISATION :
#   var xbow: WeaponData = load("res://weapons/crossbow.tres")
#   weapon_controller.set_weapon(xbow)
# ============================================

class_name WeaponData
extends Resource

# Types d'armes supportés. Le WeaponController dispatche selon ce type.
# Pour ajouter un nouveau type (ex: MAGIC_STAFF) : ajouter ici + gérer dans controller.
enum WeaponType {
	RANGED_CROSSBOW,  # Arbalète : raycast + projectile qui se plante
	MELEE_SWORD,      # Épée : hit de proximité en cône devant
	# À AJOUTER PLUS TARD :
	# RANGED_BOW_LONG,  # Arc long : charge avant tir
	# RANGED_BOW_SHORT, # Arc court : cadence rapide, dégâts faibles
	# MAGIC_STAFF,      # Bâton magique : projectile à effet
}

# === IDENTITÉ ===
@export var id: String = ""                  # Identifiant unique (ex: "crossbow")
@export var weapon_name: String = ""         # Nom affiché (ex: "Arbalète")
@export var type: WeaponType = WeaponType.RANGED_CROSSBOW

# === STATS DE COMBAT ===
@export var damage: int = 10                 # Dégâts par hit
@export var cooldown: float = 1.0            # Secondes entre attaques
@export var range_max: float = 20.0          # Portée (pour ranged, distance raycast)

# === AMMUNITION (pour armes à projectile) ===
# -1 = illimité (épée, mêlée)
@export var ammo_max: int = -1
@export var reload_time: float = 0.0

# === AUDIO ===
@export var sound_shoot: AudioStream         # Son à l'attaque
@export var sound_volume_db: float = -12.0

# === POUR PLUS TARD (préparés mais pas utilisés tant que non switch) ===
@export var icon: Texture2D                  # Icône HUD pour le slot
@export var knockback_force: float = 0.0     # Force de push sur hit (deferred)
