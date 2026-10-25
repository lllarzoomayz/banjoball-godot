extends RefCounted
## Independent original global node tracks for opted-in scenery models.
const Tracks=preload("res://scripts/wc3_uv.gd")
const CONVERSION=Basis(Vector3.RIGHT,Vector3(0,0,-1),Vector3.UP)
static func apply(model):
	var camera=model.get_viewport().get_camera_3d()
	var facing=Basis.IDENTITY
	if camera!=null:
		facing=CONVERSION.inverse()*model.global_basis.orthonormalized().inverse()*Basis(camera.global_basis.z,camera.global_basis.x,camera.global_basis.y)
	var poses={};var frame=float(model.clip.interval[0])+model.animation_time*1000
	for node in model.data.live_pose_nodes:
		var t=Tracks.sample(node.get("translation"),[0,0,0],frame,model.clip.interval,model.visual_time,model.data.global_sequences)
		var r=Tracks.sample(node.get("rotation"),[0,0,0,1],frame,model.clip.interval,model.visual_time,model.data.global_sequences,true)
		var s=Tracks.sample(node.get("scaling"),[1,1,1],frame,model.clip.interval,model.visual_time,model.data.global_sequences)
		var pivot=Vector3(node.pivot[0],node.pivot[1],node.pivot[2])
		var basis=Basis(Quaternion(r[0],r[1],r[2],r[3]))*Basis.from_scale(Vector3(s[0],s[1],s[2]))
		var pose=Transform3D(basis,Vector3(t[0],t[1],t[2])+pivot-basis*pivot)
		if node.parent!=null:pose=poses[int(node.parent)]*pose
		var flags=int(node.get("flags",0))
		if camera!=null and flags&120:
			var transformed_pivot=pose*pivot
			if flags&8:
				if node.parent!=null:
					var inverse_parent=Basis(poses[int(node.parent)].basis.get_rotation_quaternion().inverse())
					pose=Transform3D(inverse_parent,transformed_pivot-inverse_parent*transformed_pivot)*pose
				pose=Transform3D(facing,transformed_pivot-facing*transformed_pivot)*pose
			else:
				var axis=pose.basis.x if flags&16 else (pose.basis.y if flags&32 else pose.basis.z)
				var target=axis.cross(axis.cross(-facing.x)).normalized()
				if target.length_squared()>0 and pose.basis.x.length_squared()>0:
					var locked=Basis(Quaternion(pose.basis.x.normalized(),target))
					pose=Transform3D(locked,transformed_pivot-locked*transformed_pivot)*pose
		poses[int(node.id)]=pose
	for i in range(model.data.bone_ids.size()):
		var pose: Transform3D=poses[int(model.data.bone_ids[i])]
		model.skeleton.set_bone_pose(i,Transform3D(CONVERSION*pose.basis*CONVERSION.inverse(),CONVERSION*pose.origin/100.0))
