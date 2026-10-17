## Direct production projection-stage regression for packed thin/degenerate input.
## --before executes the preserved 350-check revision with the same assertions.
extends SceneTree
const Mapper=preload("res://plugins/builtin/shape_tracks/projection.gd")
class IdentityGeometry extends RefCounted:
	func x_of(x:float,_s:float)->float:return x
	func y_of(s:float)->float:return s
class IdentityRenderer extends RefCounted:
	var G=IdentityGeometry.new()
	func visual_progress(_id:int,time:float)->float:return time
	func visual_time(_id:int,p:float)->float:return p
	func s_of_p(p:float)->float:return p
var checks:=0
var failures:=0
var before:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func run_case(label:String,poly:Array,expectation:String)->void:
	var mapper=load(get_script().resource_path.get_base_dir().path_join("fixtures/projection_before_strict_triangulation.gd")) if before else Mapper
	var r=IdentityRenderer.new()
	var original:=poly.duplicate(true);var work:Dictionary=mapper.budget(r,0,-2.,12.,65536)
	var data:Dictionary=mapper.polygon(r,0,poly,work)
	var points:PackedVector2Array=data.get("points",PackedVector2Array());var indices:PackedInt32Array=data.get("indices",PackedInt32Array())
	var error:=str(work.error);var finite:=true;var valid:=indices.size()%3==0
	for point in points:finite=finite and point.is_finite()
	for index in indices:valid=valid and index>=0 and index<points.size()
	check(poly==original,label+" input ownership preserved")
	check(finite and valid,label+" finite valid real projected arrays")
	check(error.is_empty() or data.is_empty(),label+" error cannot return partial mesh")
	if expectation=="visible":check(error.is_empty() and not indices.is_empty(),label+" finite legal thin polygon stays visible")
	elif expectation=="degenerate":
		var zero_area:=true
		for i in range(0,indices.size(),3):
			var a:Vector2=points[indices[i]];var b:Vector2=points[indices[i+1]];var c:Vector2=points[indices[i+2]]
			zero_area=zero_area and (float(b.x)-float(a.x))*(float(c.y)-float(a.y))-(float(b.y)-float(a.y))*(float(c.x)-float(a.x))==0.0
		check(error.is_empty() and zero_area,label+" actual packed degenerate primitives have zero raster area")
	elif expectation=="diagnostic":check(not error.is_empty() and indices.is_empty(),label+" non-collinear cancelled area is diagnosed")
	else:check(not indices.is_empty() or not error.is_empty(),label+" non-collinear thin polygon cannot silently disappear")
	print("TRIANGULATION ",label," vertices=",points.size()," triangles=",indices.size()/3," diagnostic=",error)
func _init()->void:
	before="--before" in OS.get_cmdline_user_args()
	run_case("one-ulp vertical",[[1000.,100.],[1000.+pow(2.,-14),100.],[1000.+pow(2.,-14),100.25],[1000.,100.25]],"visible")
	run_case("one-ulp horizontal",[[100.,1000.],[100.25,1000.],[100.25,1000.+pow(2.,-14)],[100.,1000.+pow(2.,-14)]],"visible")
	run_case("non-collinear narrow diagonal",[[0.,0.],[1.,1.],[1.,1.+pow(2.,-23)],[0.,pow(2.,-23)]],"visible_or_diagnostic")
	run_case("cancelled signed area",[[10.,10.],[11.,11.],[10.,11.],[11.,10.]],"diagnostic")
	run_case("small cancelled signed area",[[0.,0.],[.0001,.0001],[0.,.0001],[.0001,0.]],"diagnostic")
	run_case("packed zero width",[[1000.,100.],[1000.+1e-10,100.],[1000.+1e-10,101.],[1000.,101.]],"degenerate")
	run_case("strictly collinear",[[10.,10.],[11.,11.],[12.,12.]],"degenerate")
	run_case("finite packed extremes",[[-2e38,2.],[2e38,2.],[2e38,3.],[-2e38,3.]],"visible")
	print("PROJECTION TRIANGULATION ","before" if before else "after",": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
