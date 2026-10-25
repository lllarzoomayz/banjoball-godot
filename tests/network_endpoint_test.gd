extends SceneTree
const Endpoint=preload("res://scripts/net_endpoint.gd")
const RoomCode=preload("res://scripts/net_room_code.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():
	for value in ["192.168.0.103", "example.com", "localhost"]:
		check(Endpoint.parse(value).get("port")==27888,"default port: "+value)
	check(Endpoint.parse(" relay.example.com:45123 ")=={"host":"relay.example.com","port":45123},"relay assigned port")
	check(Endpoint.parse("[2001:db8::1]:45123")=={"host":"2001:db8::1","port":45123},"bracketed IPv6")
	check(Endpoint.parse("2001:db8::1").get("port")==27888,"bare IPv6")
	for value in ["", " ", "https://playit.gg", "example.com/path", "x:0", "x:65536", "x:-1", "x:+1", "x:abc", "x:", "x:1:2", "[x]:2", "[::1]evil", "[::1]:", "a b", "a@b", "bad..host", "-bad.host", "bad-.host"]:
		check(Endpoint.parse(value).is_empty(),"reject malformed endpoint: "+value)
	print("ENDPOINT: host, assigned port, IPv6 and invalid input checked; failures=",failures)
	check(RoomCode.normalize("a1b-2c3")=="A1B2C3","room code case and separator")
	check(RoomCode.normalize("invalid")=="","reject wrong room code")
	check(RoomCode.find_room([{"id":"a1b2c3abcdef"}],"A1B2C3")=="a1b2c3abcdef","room code lookup")
	check(RoomCode.find_room([{"id":"a1b2c3abcdef"},{"id":"a1b2c3000000"}],"A1B2C3")=="","never join an ambiguous room code")
	quit(1 if failures else 0)
