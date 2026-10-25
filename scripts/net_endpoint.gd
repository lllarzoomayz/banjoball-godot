extends RefCounted
# Public UDP relays usually allocate a different port from the NAS listener.
static func parse(value: String, default_port: int=27888) -> Dictionary:
	var text=value.strip_edges()
	if text.is_empty() or text.length()>320:return {}
	var hostname=text
	var port=default_port
	var port_text=""
	if text.begins_with("["):
		var end=text.find("]")
		if end<2:return {}
		hostname=text.substr(1,end-1)
		if not hostname.is_valid_ip_address() or not ":" in hostname:return {}
		var tail=text.substr(end+1)
		if not tail.is_empty():
			if not tail.begins_with(":"):return {}
			port_text=tail.substr(1)
			if port_text.is_empty():return {}
	elif text.count(":")==1:
		var pair=text.split(":")
		hostname=pair[0];port_text=pair[1]
		if port_text.is_empty():return {}
	elif text.count(":")>1:
		if not text.is_valid_ip_address():return {}
	if not port_text.is_empty():
		for character in port_text:
			if not character in "0123456789":return {}
		port=int(port_text)
	if port<1 or port>65535:return {}
	if not hostname.is_valid_ip_address():
		if hostname.is_empty() or hostname.length()>253:return {}
		for label in hostname.trim_suffix(".").split("."):
			if label.is_empty() or label.length()>63 or label.begins_with("-") or label.ends_with("-"):return {}
			for character in label.to_lower():
				if not character in "abcdefghijklmnopqrstuvwxyz0123456789-":return {}
	return {"host":hostname.to_lower(),"port":port}

static func packaged_address() -> String:
	var path="res://assets/network/endpoints.json"
	if FileAccess.file_exists(path):
		var config=JSON.parse_string(FileAccess.get_file_as_string(path))
		if config is Dictionary:
			var public_address=str(config.get("public",""))
			if not parse(public_address).is_empty():return public_address
	return "127.0.0.1"

static func packaged_deployment() -> String:
	var path="res://assets/network/endpoints.json"
	if FileAccess.file_exists(path):
		var config=JSON.parse_string(FileAccess.get_file_as_string(path))
		if config is Dictionary:return str(config.get("deployment",""))
	return ""
