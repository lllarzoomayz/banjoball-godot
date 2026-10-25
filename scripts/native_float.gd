extends RefCounted
## Local 1.27 software arithmetic reconstructed from x86 and checked bit-for-bit.
## Bounded finite gameplay inputs only. This does not reproduce the scheduler.
const MASK=0xffffffff
static var lookup: Dictionary={}

static func u32(a: int) -> int:return a&MASK
static func s32(a: int) -> int:return (a&0x7fffffff)-(a&0x80000000)
static func bits(v: float) -> int:
	var b=PackedByteArray();b.resize(4);b.encode_float(0,v)
	return b.decode_u32(0)
static func value(v: int) -> float:
	var b=PackedByteArray();b.resize(4);b.encode_u32(0,u32(v))
	return b.decode_float(0)
static func bit_length(v: int) -> int:
	var count=0
	while v>0:v>>=1;count+=1
	return count
static func mul_high(a: int,b: int) -> int:
	# Unsigned high half, avoiding a signed 64-bit intermediate overflow.
	var low=(a&65535)*(b&65535)
	var middle=(low>>16)+(a>>16)*(b&65535)+(a&65535)*(b>>16)
	return u32((middle>>16)+(a>>16)*(b>>16))
static func table(name: String) -> Array:
	if lookup.is_empty():
		var data=JSON.parse_string(FileAccess.get_file_as_string("res://research/native-math-tables.json"))
		for key in data.tables:lookup[key]=data.tables[key].values
	return lookup[name]
static func multiply(a: int,b: int) -> int:
	var sign_bit=(a^b)&0x80000000
	var ae=a&0x7f800000;var be=b&0x7f800000
	var am=a&0x7fffff;var bm=b&0x7fffff
	if am!=0 and bm!=0:
		var exponent=u32(ae-0x3f800000+be)
		var high=mul_high((am|0x800000)<<8,(bm|0x800000)<<8)
		var shift=high>>31
		var fraction=(high>>(shift+7))&0x7fffff
		return 0 if s32(exponent-0x800000)<0 else u32(fraction|u32(exponent+(shift<<23))|sign_bit)
	if ae==0 or be==0:return 0
	var exponent=u32(ae+be-0x3f800000)
	return 0 if s32(exponent-0x800000)<0 else u32(exponent|am|bm|sign_bit)
static func integer_root(v: int) -> int:
	var remainder=0;var twice_root=0
	for i in range(16):
		remainder=(remainder<<2)|(v>>30)
		twice_root*=2
		v=u32(v<<2)
		if twice_root<remainder:remainder-=twice_root+1;twice_root+=2
	return twice_root>>1
static func square_root(a: int) -> int:
	if s32(a)<=0:return 0
	var mantissa=a&0x7fffff
	var exponent=((a>>23)&255)-127
	var expanded=u32((mantissa|0xff800000)<<8)|(mantissa>>15)
	var root=integer_root(expanded)
	var significand=(u32((root-0xb504)*0xb505)>>8)|0x3f800000
	var scale=(((exponent>>1)+127)<<23)|(0x3504f3 if exponent&1 else 0)
	return multiply(scale,significand)
static func add(a: int,b: int) -> int:
	var ae=a&0x7f800000;var be=b&0x7f800000
	if ae==0:return b
	if be==0:return a
	var am=((a&0x7fffff)|0x800000)*(-2 if a&0x80000000 else 2)
	var bm=((b&0x7fffff)|0x800000)*(-2 if b&0x80000000 else 2)
	var shift=(be-ae)>>23
	if shift>=23:return b
	if shift<=-23:return a
	var exponent=maxi(ae,be)
	if shift>0:am>>=shift
	else:bm>>=-shift
	var total=am+bm
	if total==0:return 0
	var mantissa=absi(total);shift=bit_length(mantissa)-24
	mantissa=mantissa>>shift if shift>=0 else mantissa<<(-shift)
	return u32(exponent+((shift-1)<<23))|(mantissa&0x7fffff)|(0x80000000 if total<0 else 0)
static func subtract(a: int,b: int) -> int:return add(a,b^0x80000000)
static func reciprocal(a: int) -> int:
	var t=table("reciprocal");var m=a&0x7fffff;var i=m>>13
	var fraction=u32(m<<19)
	fraction=(fraction>>13)|fraction
	fraction=(fraction>>13)|u32(m<<19)
	var out=u32(int(t[i])-mul_high(u32(int(t[i])-int(t[i+1])),fraction)-(a&0x7f800000)+0x7e800000)
	return 0 if s32(out-0x800000)<0 else out|(a&0x80000000)
static func divide(a: int,b: int) -> int:return 0x3f800000 if a==b else multiply(a,reciprocal(b))
static func integer_float(a: int) -> int:
	a=s32(a)
	if a==0:return 0
	var magnitude=absi(a);var exponent=bit_length(magnitude)-1;var shift=exponent-23
	var mantissa=magnitude>>shift if shift>=0 else magnitude<<(-shift)
	return ((exponent+127)<<23)|(mantissa&0x7fffff)|(0x80000000 if a<0 else 0)
static func float_integer(a: int) -> int:
	var exponent=(a>>23)&255
	if exponent<127:return 0
	var m=(a&0x7fffff)|0x800000;var shift=150-exponent
	var result=m>>shift if shift>=0 else u32(m<<(-shift))
	return -result if a&0x80000000 else result
static func arc_cos(a: int) -> int:
	var absolute=a&0x7fffffff
	if absolute<=0x3f7e8000:
		var v=clampi(float_integer(u32(a+0xf000000)),-0x3fffffff,0x3fffffff)
		var fraction=u32(v<<12);fraction|=fraction>>20
		var index=(v>>20)&1023;var t=table("acos")
		var start: int;var diff: int
		if v>=0:start=int(t[index]);diff=u32(start-int(t[index+1]))
		else:start=u32(0x6487ed51-int(t[1024-index]));diff=u32(int(t[1023-index])-int(t[1024-index]))
		var out=integer_float(u32(start-mul_high(diff,fraction)))
		return u32(out-(0xe800000 if out&0x7f800000 else 0))
	absolute=mini(absolute,0x3f800000)
	var gap=0x3f800000-absolute;var leading=32-bit_length(gap)
	var fraction=u32((~gap)<<leading) if leading<32 else 0
	var index=(leading*8-120)|(fraction>>28);fraction=u32(fraction<<4)
	var t=table("acos_near_one");var start=int(t[index]);var diff=u32(start-int(t[index+1]))
	var out=integer_float(u32(start-mul_high(diff,fraction)))
	out=u32(out-(0x11000000 if out&0x7f800000 else 0))
	return subtract(0x40490fdb,out) if a&0x80000000 else out
static func direction(x: int,y: int) -> int:
	var length=square_root(add(multiply(x,x),multiply(y,y)))
	if (length&0x7fffffff)<=0x3727c5ac:return 0
	var angle=arc_cos(divide(x,length))
	if (angle&0x7fffffff)<=0x3727c5ac:return 0
	return subtract(0x40c90fdb,angle) if value(y)<0 else angle
static func angle_error(x: int,y: int,facing: int) -> int:
	var raw=subtract(facing,direction(x,y));var out: int
	if value(raw)<0:
		out=subtract(0xc0c90fdb,raw) if (raw&0x7fffffff)>0x40490fdb else raw^0x80000000
	else:
		# Compare numerically so a negative-zero bit pattern remains zero.
		out=subtract(0x40c90fdb,raw) if value(raw)>value(0x40490fdb) else raw^0x80000000
	return 0 if absf(value(out))<value(0x3456bf95) else out
static func movement_geometry(delta: Vector2,facing: float) -> Vector2:
	var x=bits(delta.x/32.0);var y=bits(delta.y/32.0)
	var f=bits(fposmod(facing,TAU))
	return Vector2(value(square_root(add(multiply(x,x),multiply(y,y))))*32.0,value(angle_error(x,y,f)))
static func squared_distance(ax: int,ay: int,bx: int,by: int) -> int:
	var x=subtract(ax,bx);var y=subtract(ay,by)
	return add(multiply(x,x),multiply(y,y))
static func waypoint_reached(from: Vector2,to: Vector2) -> bool:
	# 0x1137c0 compares squared internal coordinates, without sqrt or heading.
	var distance=squared_distance(bits(from.x/32.0),bits(from.y/32.0),bits(to.x/32.0),bits(to.y/32.0))
	return value(distance)<=value(multiply(0x3efae148,0x3efae148))
