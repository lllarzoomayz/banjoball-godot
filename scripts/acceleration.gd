extends RefCounted
## The packaged native module accelerates identical calculations. Keep the
## script implementation available for parity tests and unsupported platforms.
static func create():
	if "--script-only" not in OS.get_cmdline_user_args() and ClassDB.class_exists("BanjoAccelerator"):
		return ClassDB.instantiate("BanjoAccelerator")
	return null
