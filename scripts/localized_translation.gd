extends Translation
## Godot translates display text without changing source strings used by rules.
## Exact catalog entries cover labels; templates also handle existing formatted
## scoreboards/notices. Cache is bounded so match clocks cannot grow it forever.
var catalog: Dictionary
var templates=[]
var fragments=RegEx.new()
var cache={}
func escape(value: String) -> String:
	var result=""
	for c in value:
		if c in "\\.^$|?*+()[]{}":result+="\\"
		result+=c
	return result
func _init(language: String="en"):
	locale=language
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/i18n/"+language+".json"))
	var format=RegEx.new();format.compile("%[0-9.]*[sdf]")
	var literals=[]
	for source in catalog:
		var tokens=format.search_all(source)
		if tokens.is_empty():literals.append(source);continue
		var pattern="";var at=0;var marker=""
		for token in tokens:
			var literal=source.substr(at,token.get_start()-at)
			if literal.length()>marker.length():marker=literal
			pattern+=escape(literal)
			pattern+="([^\\n]+?)" if token.get_string().ends_with("s") else "([-+]?[0-9]+(?:\\.[0-9]+)?)"
			at=token.get_end()
		var tail=source.substr(at);pattern+=escape(tail)
		if tail.length()>marker.length():marker=tail
		if tokens[-1].get_string().ends_with("s") and tail=="":pattern=pattern.trim_suffix("([^\\n]+?)")+"([^\\n]+)"
		var translated: String=catalog[source];var output="";at=0;var n=0
		for token in format.search_all(translated):
			output+=translated.substr(at,token.get_start()-at)+"{"+str(n)+"}";n+=1;at=token.get_end()
		output+=translated.substr(at)
		var regex=RegEx.new();regex.compile(pattern)
		templates.append({"regex":regex,"output":output,"marker":marker,"size":source.length()})
	templates.sort_custom(func(a,b):return a.size>b.size)
	literals.sort_custom(func(a,b):return a.length()>b.length())
	var patterns=PackedStringArray()
	for source in literals:patterns.append(escape(source))
	fragments.compile("|".join(patterns))
func render_text(value: String,depth: int=0) -> String:
	if catalog.has(value):return catalog[value]
	if depth>4:return value
	var result=value
	for row in templates:
		if not result.contains(row.marker):continue
		var matches=row.regex.search_all(result)
		matches.reverse()
		for hit in matches:
			var replacement: String=row.output
			for i in range(1,hit.get_group_count()+1):replacement=replacement.replace("{"+str(i-1)+"}",render_text(hit.get_string(i),depth+1))
			result=result.substr(0,hit.get_start())+replacement+result.substr(hit.get_end())
	var matches=fragments.search_all(result);matches.reverse()
	for hit in matches:result=result.substr(0,hit.get_start())+str(catalog[hit.get_string()])+result.substr(hit.get_end())
	return result
func _get_message(src_message: StringName,_context: StringName) -> StringName:
	var source=String(src_message)
	if catalog.has(source):return StringName(catalog[source])
	if cache.has(source):return StringName(cache[source])
	var result=render_text(source)
	if cache.size()>=1024:cache.clear()
	cache[source]=result
	return StringName(result) if result!=source else &""
