extends RefCounted
const VERSION=1
const PORT=27888
const DISCOVERY=27889
const MAX_PACKET=524288
const COMMANDS=["move","move_order","move_direction","move_release","stop","hold","kick","tackle","ability","ability_secondary","sprint","morph_reset","shout","taunt","sadface","pass"]

static func encode(value: Dictionary) -> PackedByteArray:
	return var_to_bytes(value).compress(FileAccess.COMPRESSION_DEFLATE)

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size()>MAX_PACKET:return {}
	var raw=bytes.decompress_dynamic(MAX_PACKET,FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():return {}
	var value=bytes_to_var(raw) # Objects are never decoded.
	return value if value is Dictionary else {}

static func send(peer: ENetPacketPeer,value: Dictionary,reliable=true):
	if peer!=null and peer.get_state()==ENetPacketPeer.STATE_CONNECTED:
		peer.send(0 if reliable else 1,encode(value),ENetPacketPeer.FLAG_RELIABLE if reliable else 0)

static func uuid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
