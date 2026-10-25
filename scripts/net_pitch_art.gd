extends Control
## Static pitch motif, not an exact map preview or a running simulation.
var field=0
func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE;resized.connect(queue_redraw)
func _draw():
	var rect=Rect2(Vector2(8,8),size-Vector2(16,16));var colors=[Color("30513a"),Color("3c5043"),Color("344c59"),Color("524438")]
	var style=StyleBoxFlat.new();style.bg_color=colors[posmod(field,colors.size())];style.set_corner_radius_all(12);draw_style_box(style,rect)
	var pitch=rect.grow(-12);var ink=Color(.78,.88,.74,.36)
	for i in range(6):
		if i%2==0:draw_rect(Rect2(pitch.position+Vector2(pitch.size.x*i/6,0),Vector2(pitch.size.x/6,pitch.size.y)),Color(1,1,1,.025))
	draw_rect(pitch,ink,false,1.5);draw_line(Vector2(pitch.get_center().x,pitch.position.y),Vector2(pitch.get_center().x,pitch.end.y),ink,1.5,true)
	draw_arc(pitch.get_center(),minf(pitch.size.x,pitch.size.y)*.21,0,TAU,48,ink,1.5,true)
	for side in [0,1]:
		var w=pitch.size.x*.14;var h=pitch.size.y*.48;draw_rect(Rect2(Vector2(pitch.position.x if side==0 else pitch.end.x-w,pitch.get_center().y-h/2),Vector2(w,h)),ink,false,1.5)
	draw_circle(pitch.get_center(),3,Color("e4c27a"))
