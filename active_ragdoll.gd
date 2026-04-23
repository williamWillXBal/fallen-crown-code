# ============================================
# ACTIVE_RAGDOLL.GD — Module de poses cibles pour ragdoll active
# ============================================
# PHASE 1 ✅ : Infrastructure + 1 pose de base
# PHASE 2 ✅ (ACTUELLE) : Contrôleur PID quaternion
# PHASE 3 : Intégration dans enemy.gd (remplacement physique pure)
# PHASE 4 : Ajout variantes multiples de poses (random)
# PHASE 5 : Polish final (timing, auto-righting)
# ============================================
#
# CONCEPT: Au lieu de laisser la physique pure gérer la chute (qui donne parfois
# des positions chelous à mi-distance), on applique des torques correctifs sur
# chaque joint pour ramener progressivement le corps vers une pose "cadavre
# étalé" naturelle.
#
# La physique initiale (impact, projection) reste identique les ~0.5 premières
# secondes pour garder le spectacle. Ensuite le PID s'active progressivement
# (ramp_factor de 0 à 1 sur ramp_up_time) et guide le corps vers la pose cible.
#
# FONCTIONS (Ctrl+F sur le nom) :
#   get_random_pose()                → Retourne une pose aléatoire
#   _get_all_poses()                 → Liste des poses disponibles
#   setup(rbs, pose, body_basis)     → Initialise les controllers (Phase 3)
#   _physics_process(delta)          → Boucle auto de mise à jour PID
#
# CLASSE INTERNE :
#   JointController                  → PID quaternion pour un RB
#     update(delta, ramp_factor)     → Calcule et applique le torque
# ============================================

extends Node
class_name ActiveRagdoll

# -------- POSES CIBLES --------
# Chaque pose = Dictionary {nom_RB: Vector3(rotation_euler_radians)}
# Rotations exprimées dans le repère LOCAL du mort (avant body_basis global).
# Convention : X = tangage (pitch), Y = lacet (yaw), Z = roulis (roll)
#
# Pour un cadavre sur le dos : X = -1.57 (-90°) = corps basculé sur le dos.

# POSE_BACK_SPREAD : Sur le dos.
# Gains différenciés :
#   - Tronc (torso, pelvis) : kp=5, kd=8 → forcer la position couchée
#   - Membres parents (bras, cuisses) : kp=1, kd=4 → suggérer sans conflit
#   - Extrémités (tête, avant-bras, mollets) : kp=0.5, kd=3 → aligner très doucement
# Tous les RBs visent une rotation X=-1.57 (allongé avec le tronc) pour
# obtenir une silhouette couchée cohérente sans plier bizarrement.
const POSE_BACK_SPREAD := {
	"torso_top": {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 30.0, "kd": 15.0},
	"pelvis":    {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 30.0, "kd": 15.0},
	"upper_l":   {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 1.0, "kd": 4.0},
	"upper_r":   {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 1.0, "kd": 4.0},
	"thigh_l":   {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 1.0, "kd": 4.0},
	"thigh_r":   {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 1.0, "kd": 4.0},
	"head":      {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 0.5, "kd": 3.0},
	"lower_l":   {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 0.5, "kd": 3.0},
	"lower_r":   {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 0.5, "kd": 3.0},
	"calf_l":    {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 0.5, "kd": 3.0},
	"calf_r":    {"euler": Vector3(-1.57, 0.0, 0.0), "kp": 0.5, "kd": 3.0},
}

# Liste de toutes les poses disponibles.
# Phase 1 : 1 pose (POSE_BACK_SPREAD).
# Phase 4 : ajouter POSE_FACE_DOWN, POSE_SIDE_FETAL, etc.
static func _get_all_poses() -> Array:
	return [POSE_BACK_SPREAD]

static func get_random_pose() -> Dictionary:
	var poses = _get_all_poses()
	return poses[randi() % poses.size()]

# -------- ÉTAT INTERNE (runtime, par instance) --------
var controllers: Array = []
var time_alive: float = 0.0

# Paramètres de timing (ajustables)
@export var ramp_up_delay: float = 0.5   # délai avant activation PID
@export var ramp_up_time: float = 1.0    # temps pour atteindre gains max
@export var max_lifetime: float = 6.0    # auto-destruct après N secondes

# -------- SETUP (appelé depuis enemy.gd en Phase 3) --------
# rbs = Dictionary {"head": RigidBody3D, "torso_top": RigidBody3D, ...}
# pose = Dictionary {rb_name: {"euler": Vector3, "kp": float, "kd": float}}
# body_basis = orientation globale du mort au moment du spawn
func setup(rbs: Dictionary, pose: Dictionary, body_basis: Basis) -> void:
	for rb_name in pose:
		if rbs.has(rb_name) and is_instance_valid(rbs[rb_name]):
			var entry = pose[rb_name]
			# Convertir la pose locale en rotation globale via body_basis
			var target_local_quat = Quaternion.from_euler(entry["euler"])
			var body_quat = body_basis.get_rotation_quaternion()
			var target_global_quat = body_quat * target_local_quat
			controllers.append(JointController.new(
				rbs[rb_name],
				target_global_quat,
				entry["kp"],
				entry["kd"]
			))

# -------- BOUCLE PAR FRAME --------
func _physics_process(delta: float) -> void:
	time_alive += delta

	# Auto-destruct après max_lifetime (économie CPU)
	if time_alive > max_lifetime:
		queue_free()
		return

	# Calculer ramp_factor : 0 pendant ramp_up_delay, puis monte à 1 sur ramp_up_time
	var ramp_factor: float = 0.0
	if time_alive > ramp_up_delay:
		ramp_factor = clampf((time_alive - ramp_up_delay) / ramp_up_time, 0.0, 1.0)

	# Appliquer PID à chaque controller
	for c in controllers:
		c.update(delta, ramp_factor)

# ============================================
# CLASSE INTERNE : JointController
# ============================================
# PID quaternion pour un RigidBody3D.
# P = torque proportionnel à l'erreur angulaire (rappel vers target)
# D = amortissement sur la vitesse angulaire (évite les oscillations)
class JointController:
	var rb: RigidBody3D
	var target_quat: Quaternion
	var kp: float   # gain proportionnel (rappel)
	var kd: float   # gain dérivé (amortissement)

	func _init(_rb: RigidBody3D, _target_quat: Quaternion, _kp: float = 5.0, _kd: float = 8.0) -> void:
		rb = _rb
		target_quat = _target_quat
		kp = _kp
		kd = _kd

	func update(_delta: float, ramp: float) -> void:
		if not is_instance_valid(rb):
			return

		# Rotation actuelle du RB en quaternion global
		var current_quat: Quaternion = rb.global_basis.get_rotation_quaternion()

		# Erreur : q_error = q_target * q_current.inverse()
		# Représente la rotation nécessaire pour aller de current vers target
		var error_quat: Quaternion = target_quat * current_quat.inverse()

		# Forcer le chemin le plus court (hémisphère positif du quaternion)
		if error_quat.w < 0.0:
			error_quat = -error_quat

		# Convertir en axis-angle pour obtenir un vecteur torque
		# angle = 2 * acos(w), axis = (x,y,z).normalized()
		var w_clamped: float = clampf(error_quat.w, -1.0, 1.0)
		var angle_mag: float = 2.0 * acos(w_clamped)
		var axis_vec: Vector3 = Vector3(error_quat.x, error_quat.y, error_quat.z)

		var torque_dir: Vector3
		if axis_vec.length() < 0.0001:
			torque_dir = Vector3.ZERO
		else:
			torque_dir = axis_vec.normalized() * angle_mag

		# Loi PID : torque = kp * erreur - kd * vitesse_angulaire
		# Le ramp_factor module les gains (0 au début, 1 après ramp complet)
		var torque: Vector3 = torque_dir * kp * ramp - rb.angular_velocity * kd * ramp

		rb.apply_torque(torque)
