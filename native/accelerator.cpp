// Hot loops only. The script versions remain the independent reference/fallback.
// No threads, changed search budgets, reduced particles, or simulation clocks.
#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <vector>
#include <cmath>
#include <algorithm>
#include <limits>
using namespace godot;

class BanjoAccelerator : public RefCounted {
    GDCLASS(BanjoAccelerator, RefCounted)
    struct Entry { int priority, id, version; };
    std::vector<Entry> heap;
    std::vector<int> scores, parents, versions;
    // Build in native storage. PackedArray::append crosses the extension API
    // for every component; transfer complete contiguous buffers only on commit.
    std::vector<Vector3> vertices;
    std::vector<Color> colors;
    std::vector<Vector2> uvs;
    std::vector<int32_t> indices;
    const Variant age_key=String("age"),gravity_key=String("gravity"),velocity_key=String("velocity"),pos_key=String("pos"),scale_key=String("scale"),angle_key=String("angle");
    // Reuse immutable dictionary keys instead of constructing engine strings per emitter.
    const Variant field_Alpha=String("Alpha");
    const Variant field_Columns=String("Columns");
    const Variant field_DecayUVAnim=String("DecayUVAnim");
    const Variant field_Flags=String("Flags");
    const Variant field_FrameFlags=String("FrameFlags");
    const Variant field_LifeSpan=String("LifeSpan");
    const Variant field_LifeSpanUVAnim=String("LifeSpanUVAnim");
    const Variant field_ParticleScaling=String("ParticleScaling");
    const Variant field_PivotPoint=String("PivotPoint");
    const Variant field_Rows=String("Rows");
    const Variant field_SegmentColor=String("SegmentColor");
    const Variant field_Squirt=String("Squirt");
    const Variant field_TailDecayUVAnim=String("TailDecayUVAnim");
    const Variant field_TailLength=String("TailLength");
    const Variant field_TailUVAnim=String("TailUVAnim");
    const Variant field_Time=String("Time");
    const Variant field_affected=String("affected");
    const Variant field_bone_index=String("bone_index");
    const Variant field_credit=String("credit");
    const Variant field_key=String("key");
    const Variant field_particles=String("particles"),field_packed=String("packed"),field_capacity=String("capacity");
    const Variant field_pivot=String("pivot");
    const Variant field_source=String("source");
    static constexpr int dx[8]={0,1,0,-1,1,1,-1,-1};
    static constexpr int dy[8]={-1,0,1,0,-1,1,1,-1};
    static constexpr int corners[4]={3,6,12,9};
    void push(Entry item) {
        int i=int(heap.size()); heap.push_back(item);
        while(i>0) { int p=(i-1)>>1; if(heap[p].priority<item.priority)break; heap[i]=heap[p];i=p; }
        heap[i]=item;
    }
    Entry pop() {
        Entry result=heap.front(),last=heap.back();heap.pop_back();
        if(heap.empty())return result;
        int i=0;
        while(i*2+1<int(heap.size())) {
            int child=i*2+1;
            if(child+1<int(heap.size()) && heap[child+1].priority<=heap[child].priority)++child;
            if(last.priority<=heap[child].priority)break;
            heap[i]=heap[child];i=child;
        }
        heap[i]=last;return result;
    }
    static Transform3D read_transform(const float *f) {
        // Identical column layout and MDX -> Godot conversion to wc3_model.gd.
        Basis conversion(Vector3(1,0,0),Vector3(0,0,-1),Vector3(0,1,0));
        Basis basis(Vector3(f[0],f[1],f[2]),Vector3(f[4],f[5],f[6]),Vector3(f[8],f[9],f[10]));
        return Transform3D(conversion*basis*conversion.inverse(),conversion.xform(Vector3(f[12],f[13],f[14]))/100.0f);
    }
    static double lerp(double a,double b,double t) { return a+(b-a)*t; }
    static Quaternion safe_rotation(const Basis &basis) {
        // Some original Death frames hide bones using zero scale. Such a
        // basis has no rotation; Godot's checked build returns identity.
        if(basis.determinant()==0)return Quaternion();
        return basis.get_rotation_quaternion();
    }
    Rect2 tile(const Dictionary &source,const Array &track,double blend) const {
        int cols=std::max(1,int(source[field_Columns])),rows=std::max(1,int(source[field_Rows]));
        int count=std::max(1,int(track[1])-int(track[0])),repeats=std::max(1,int(track[2]));
        int frame=std::clamp(int(track[0])+std::min(count-1,int(blend*count*repeats)%count),0,cols*rows-1);
        return Rect2(float(frame%cols)/cols,float(frame/cols)/rows,1.0f/cols,1.0f/rows);
    }
    void quad(Vector3 a,Vector3 b,Vector3 c,Vector3 d,Rect2 uv,Color color) {
        int n=int(vertices.size());
        vertices.push_back(a);vertices.push_back(b);vertices.push_back(c);vertices.push_back(d);
        for(int i=0;i<4;++i)colors.push_back(color);
        uvs.push_back(uv.position);uvs.push_back(uv.position+Vector2(0,uv.size.y));uvs.push_back(uv.position+Vector2(uv.size.x,0));uvs.push_back(uv.position+uv.size);
        for(int i: {0,1,2,2,1,3})indices.push_back(n+i);
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("find_cells","width","height","start","goal","blocked"),&BanjoAccelerator::find_cells);
        ClassDB::bind_method(D_METHOD("sample_pose","frames","offset","count","first","second","blend"),&BanjoAccelerator::sample_pose);
        ClassDB::bind_method(D_METHOD("apply_pose","skeleton","poses"),&BanjoAccelerator::apply_pose);
        ClassDB::bind_method(D_METHOD("integrate_particles","particles","delta","life"),&BanjoAccelerator::integrate_particles);
        ClassDB::bind_method(D_METHOD("begin_geometry"),&BanjoAccelerator::begin_geometry);
        ClassDB::bind_method(D_METHOD("draw_particles","particles","source","transform","tint","alpha","right","up","eye"),&BanjoAccelerator::draw_particles);
        ClassDB::bind_method(D_METHOD("draw_packed_particles","particles","source","transform","tint","alpha","right","up","eye"),&BanjoAccelerator::draw_packed_particles);
        ClassDB::bind_method(D_METHOD("draw_ribbons","sections","source","clock","slot"),&BanjoAccelerator::draw_ribbons);
        ClassDB::bind_method(D_METHOD("apply_billboards","skeleton","entries","transform","camera_basis"),&BanjoAccelerator::apply_billboards);
        ClassDB::bind_method(D_METHOD("spawn_particles","particles","source","values","pose","transform","rng","count"),&BanjoAccelerator::spawn_particles);
        ClassDB::bind_method(D_METHOD("advance_emitters","emitters","tracks","frame","delta","skeleton","transform","clip","cycle","emitting","visible","rng"),&BanjoAccelerator::advance_emitters);
        ClassDB::bind_method(D_METHOD("geometry_arrays"),&BanjoAccelerator::geometry_arrays);
    }
public:
    PackedInt32Array find_cells(int width,int height,int start,int goal,const PackedByteArray &blocked) {
        PackedInt32Array result;
        // Validate before multiplication/indexing (including erroneous callers).
        if(width<=0 || height<=0 || int64_t(width)*height>10000000)return result;
        int count=width*height;
        if(blocked.size()!=count || start<0 || start>=count || goal<0 || goal>=count)return result;
        scores.assign(count,INT32_MAX);parents.assign(count,-1);versions.assign(count,0);heap.clear();
        const uint8_t *solid=blocked.ptr();
        int tx=goal%width,ty=goal/width,closest=start;
        int closest_distance=(start%width-tx)*(start%width-tx)+(start/width-ty)*(start/width-ty);
        scores[start]=0;versions[start]=1;
        push({int(std::sqrt(double(closest_distance)*576.0)),start,1});
        int expanded=0;
        while(!heap.empty() && expanded<count*3) {
            Entry item=pop();int current=item.id;
            if(item.version!=versions[current])continue;
            ++expanded;
            if(current==goal){closest=goal;break;}
            int cx=current%width,cy=current/width,mask=0;
            for(int d=0;d<8;++d) {
                if(d>=4 && (mask&corners[d-4])!=corners[d-4])continue;
                int x=cx+dx[d],y=cy+dy[d];
                if(x<0||y<0||x>=width||y>=height)continue;
                int q=y*width+x;if(solid[q])continue;
                if(d<4)mask|=1<<d;
                int score=scores[current]+(d<4?24:33);
                if(scores[q]<=score)continue;
                parents[q]=current;scores[q]=score;++versions[q];
                int distance=(x-tx)*(x-tx)+(y-ty)*(y-ty);
                push({score+int(std::sqrt(double(distance)*576.0)),q,versions[q]});
                if(distance<closest_distance){closest=q;closest_distance=distance;}
            }
        }
        for(int cursor=closest;cursor>=0;cursor=parents[cursor])result.append(cursor);
        result.reverse();return result;
    }
    Array sample_pose(const PackedFloat32Array &frames,int offset,int count,int first,int second,double blend) const {
        Array poses;
        if(offset<0||count<0||first<0||second<0||int64_t(offset)+(int64_t(std::max(first,second))+1)*count*16>frames.size())return poses;
        const float *data=frames.ptr();poses.resize(count);
        for(int i=0;i<count;++i) {
            auto a=read_transform(data+offset+(first*count+i)*16);
            auto b=read_transform(data+offset+(second*count+i)*16);
            Transform3D t;
            t.basis.set_quaternion_scale(safe_rotation(a.basis).slerp(safe_rotation(b.basis),blend).normalized(),a.basis.get_scale().lerp(b.basis.get_scale(),blend));
            t.origin=a.origin.lerp(b.origin,blend);
            Array pose;pose.append(t.origin);pose.append(safe_rotation(t.basis));pose.append(t.basis.get_scale());poses[i]=pose;
        }
        return poses;
    }
    void apply_pose(Skeleton3D *skeleton,const Array &poses) const {
        if(!skeleton || skeleton->get_bone_count()!=poses.size())return;
        for(int i=0;i<poses.size();++i) {
            Array p=poses[i];if(p.size()!=3)continue;
            skeleton->set_bone_pose_position(i,p[0]);skeleton->set_bone_pose_rotation(i,p[1]);skeleton->set_bone_pose_scale(i,p[2]);
        }
    }
    Array integrate_particles(const Array &particles,double delta,double life) const {
        Array alive;
        for(int i=0;i<particles.size();++i) {
            Dictionary p=particles[i];double age=double(p[age_key])+delta;
            Vector3 velocity=p[velocity_key];velocity.y=double(velocity.y)-double(p[gravity_key])*delta;
            Vector3 pos=p[pos_key];pos+=velocity*delta;
            p[age_key]=age;p[velocity_key]=velocity;p[pos_key]=pos;
            if(age<life)alive.append(p);
        }
        return alive;
    }
    // Dense storage is opt-in for scenery. Positions/velocities retain Vector3
    // float rounding; age and scalar parameters retain the old double precision.
    PackedFloat64Array integrate_packed(PackedFloat64Array particles,double delta,double life) const {
        double *out=particles.ptrw();int alive=0;
        for(int i=0;i<particles.size();i+=10) {
            double age=out[i+6]+delta;
            Vector3 velocity(out[i+3],out[i+4],out[i+5]);velocity.y=double(velocity.y)-out[i+9]*delta;
            Vector3 pos(out[i],out[i+1],out[i+2]);pos+=velocity*delta;
            if(age>=life)continue;
            double angle=out[i+7],scale=out[i+8],gravity=out[i+9];
            out[alive++]=pos.x;out[alive++]=pos.y;out[alive++]=pos.z;
            out[alive++]=velocity.x;out[alive++]=velocity.y;out[alive++]=velocity.z;
            out[alive++]=age;out[alive++]=angle;out[alive++]=scale;out[alive++]=gravity;
        }
        particles.resize(alive);return particles;
    }
    PackedFloat64Array append_packed(PackedFloat64Array packed,const Array &particles) const {
        int offset=packed.size();packed.resize(offset+particles.size()*10);double *out=packed.ptrw();
        for(int i=0;i<particles.size();++i) {
            Dictionary p=particles[i];Vector3 pos=p[pos_key],velocity=p[velocity_key];
            out[offset++]=pos.x;out[offset++]=pos.y;out[offset++]=pos.z;
            out[offset++]=velocity.x;out[offset++]=velocity.y;out[offset++]=velocity.z;
            out[offset++]=p[age_key];out[offset++]=p[angle_key];out[offset++]=p[scale_key];out[offset++]=p[gravity_key];
        }
        return packed;
    }
    void begin_geometry(){vertices.clear();colors.clear();uvs.clear();indices.clear();}
    void advance_emitters(Array emitters,const Array &tracks,double frame,double delta,Skeleton3D *skeleton,Transform3D transform,String clip,int64_t cycle,bool emitting,bool visible,RandomNumberGenerator *rng) {
        if(tracks.is_empty() || !skeleton)return;
        int a=std::min(int(frame),int(tracks.size())-1),b=std::min(a+1,int(tracks.size())-1);
        Array first=tracks[a],second=tracks[b];double blend=frame-a;
        for(int i=0;i<emitters.size();++i) {
            Dictionary emitter=emitters[i],source=emitter[field_source];
            Array particles=emitter[field_particles];bool dense=emitter.has(field_packed);
            PackedFloat64Array packed;if(dense)packed=emitter[field_packed];
            if(!visible){particles.clear();if(dense)emitter[field_packed]=PackedFloat64Array();emitter[field_credit]=0.0;continue;}
            Array va=first[i],vb=second[i];
            if(delta>0) {
                if(dense)packed=integrate_packed(packed,delta,source[field_LifeSpan]);
                else if(!particles.is_empty())particles=integrate_particles(particles,delta,source[field_LifeSpan]);
                if(emitting && double(va[0])>0) {
                    double credit=emitter[field_credit];
                    if(bool(source[field_Squirt]) && double(va[8])>=0) {
                        String key=clip+":"+String::num_int64(cycle)+":"+String::num(double(va[8]));
                        if(String(emitter[field_key])!=key){emitter[field_key]=key;credit+=std::max(0.0,double(va[9]));}
                    } else credit+=std::max(0.0,lerp(va[5],vb[5],blend))*delta;
                    int capacity=std::max(1,std::min(4096,int(emitter.get(field_capacity,512))));
                    int count=std::max(0,std::min(int(credit),capacity-int(dense?packed.size()/10:particles.size())));
                    emitter[field_credit]=credit-std::floor(credit);
                    if(count>0) {
                        // Only emission rate is needed until a particle is actually born.
                        Array values;values.resize(10);
                        for(int j=0;j<10;++j)values[j]=(j>=1 && j<=7)?lerp(va[j],vb[j],blend):double(va[j]);
                        spawn_particles(particles,source,values,skeleton->get_bone_pose(int(source[field_bone_index])),transform,rng,count);
                        if(dense){packed=append_packed(packed,particles);particles.clear();}
                    }
                }
            }
            emitter[field_particles]=particles;if(dense)emitter[field_packed]=packed;
        }
    }
    void apply_billboards(Skeleton3D *skeleton,const Array &entries,Transform3D transform,Basis camera_basis) {
        if(!skeleton)return;
        const Basis conversion(Vector3(1,0,0),Vector3(0,0,-1),Vector3(0,1,0));
        const Basis rotation=transform.basis.orthonormalized().inverse()*Basis(camera_basis.get_column(2),camera_basis.get_column(1),-camera_basis.get_column(0));
        for(int i=0;i<entries.size();++i) {
            Dictionary entry=entries[i];int bone=entry[field_bone_index];
            Array p=entry[field_pivot];Vector3 pivot=skeleton->get_bone_pose(bone).xform(conversion.xform(Vector3(p[0],p[1],p[2]))/100.0f);
            const Transform3D facing(rotation,pivot-rotation.xform(pivot));
            Array affected=entry[field_affected];
            for(int j=0;j<affected.size();++j) {
                int index=affected[j];Transform3D result=facing*skeleton->get_bone_pose(index);
                skeleton->set_bone_pose_position(index,result.origin);
                skeleton->set_bone_pose_rotation(index,safe_rotation(result.basis));
                skeleton->set_bone_pose_scale(index,result.basis.get_scale());
            }
        }
    }
    void spawn_particles(Array particles,const Dictionary &source,const Array &values,Transform3D pose,Transform3D transform,RandomNumberGenerator *rng,int count) {
        if(!rng || double(source[field_LifeSpan])<=0 || values.size()<8 || count<=0)return;
        const Array pivot=source[field_PivotPoint];const int flags=source[field_Flags];
        const Basis conversion(Vector3(1,0,0),Vector3(0,0,-1),Vector3(0,1,0));
        const bool model_space=bool(flags&524288);const double scale=model_space?1.0:transform.basis.get_scale().x;
        const double pi=3.14159265358979323846;
        for(int i=0;i<count;++i) {
            // Keep the same RNG calls and order as the GDScript reference.
            double x=rng->randf_range(-double(values[6]),double(values[6]));
            double y=rng->randf_range(-double(values[7]),double(values[7]));
            Vector3 local(double(pivot[0])+x,double(pivot[1])+y,pivot[2]);
            double speed=double(values[1])*(1+rng->randf_range(-double(values[2]),double(values[2])));
            double angle=rng->randf_range(0,2*pi);
            double latitude=rng->randf_range(0,double(values[3])*pi/180.0);
            Vector3 velocity=Vector3(0,0,speed).rotated(Vector3(0,1,0),latitude).rotated(Vector3(0,0,1),angle);
            if(flags&131072)velocity.x=0;
            Vector3 point=pose.xform(conversion.xform(local)/100.0f);
            velocity=pose.basis.xform(conversion.xform(velocity)/100.0f);
            if(!model_space){point=transform.xform(point);velocity=transform.basis.xform(velocity);}
            Dictionary particle;particle[pos_key]=point;particle[velocity_key]=velocity;particle[age_key]=0.0;
            particle[angle_key]=angle;particle[scale_key]=scale;particle[gravity_key]=double(values[4])/100.0*scale;
            particles.append(particle);
        }
    }
    void draw_ribbons(const Array &sections,const Dictionary &source,double clock,int slot) {
        const int count=sections.size();const double life=source[field_LifeSpan];
        if(count<2 || life<=0)return;
        const int columns=std::max(1,int(source[field_Columns])),rows=std::max(1,int(source[field_Rows]));
        slot=std::clamp(slot,0,columns*rows-1);
        const double height=1.0/rows,tile_y=double(slot/columns)/rows;
        const int base=vertices.size();
        const Variant birth_key=String("birth"),above_key=String("above"),below_key=String("below");
        for(int i=0;i<count;++i) {
            Dictionary section=sections[i];double age=std::max(0.0,clock-double(section[birth_key]));
            Vector3 sag(0,0.5*double(section[gravity_key])*age*age,0);
            vertices.push_back(Vector3(section[above_key])-sag);vertices.push_back(Vector3(section[below_key])-sag);
            colors.push_back(Color(1,1,1,1));colors.push_back(Color(1,1,1,1));
            Vector2 uv((double(slot%columns)+std::clamp(age/life,0.0,1.0))/columns,tile_y);
            uvs.push_back(uv);uvs.push_back(uv+Vector2(0,height));
            if(i+1<count)for(int j: {0,1,2,2,1,3})indices.push_back(base+i*2+j);
        }
    }
    struct ParticleValue {Vector3 pos,velocity;double age,angle,scale;};
    template<class Reader> void draw_particle_values(int count,Reader read,const Dictionary &source,Transform3D transform,Color tint,double alpha,Vector3 right,Vector3 up,Vector3 eye) {
        double life=source[field_LifeSpan];if(life<=0)return;
        double midpoint=std::clamp(double(source[field_Time]),0.0001,0.9999);
        int flags=source[field_Flags],frame_flags=source[field_FrameFlags];
        Array scaling=source[field_ParticleScaling],segment_colors=source[field_SegmentColor],alphas=source[field_Alpha];
        double scale=transform.basis.get_scale().x;
        double sizes[3];Color palette[3];
        for(int i=0;i<3;++i){sizes[i]=scaling[i];Array c=segment_colors[i];palette[i]=Color(c[0],c[1],c[2],double(alphas[i])/255.0);}
        double tail_length=source[field_TailLength];
        bool single_tile=int(source[field_Columns])<=1 && int(source[field_Rows])<=1;
        Array head_uv[2]={source[field_LifeSpanUVAnim],source[field_DecayUVAnim]};
        Array tail_uv[2]={source[field_TailUVAnim],source[field_TailDecayUVAnim]};
        // Cache atlas dimensions and spans once, instead of dictionary lookups
        // for each of the thousands of individual quads.
        int columns=std::max(1,int(source[field_Columns])),rows=std::max(1,int(source[field_Rows]));
        struct Atlas {int first,count,repeats;};
        auto atlas=[](const Array &track){return Atlas{int(track[0]),std::max(1,int(track[1])-int(track[0])),std::max(1,int(track[2]))};};
        Atlas heads[2]={atlas(head_uv[0]),atlas(head_uv[1])},tails[2]={atlas(tail_uv[0]),atlas(tail_uv[1])};
        auto uv_at=[&](Atlas a,double blend){
            int frame=std::clamp(a.first+std::min(a.count-1,int(blend*a.count*a.repeats)%a.count),0,columns*rows-1);
            return Rect2(float(frame%columns)/columns,float(frame/columns)/rows,1.0f/columns,1.0f/rows);
        };
        for(int i=0;i<count;++i) {
            ParticleValue p=read(i);double t=std::clamp(p.age/life,0.0,1.0);
            int segment=t<midpoint?0:1;double blend=segment==0?t/midpoint:(t-midpoint)/(1-midpoint);
            Color color=palette[segment].lerp(palette[segment+1],blend)*tint;
            color.a*=alpha;
            double size=lerp(sizes[segment],sizes[segment+1],blend)/100.0*p.scale;
            Vector3 pos=p.pos,velocity=p.velocity;
            if(flags&524288){pos=transform.xform(pos);velocity=transform.basis.xform(velocity);size*=scale;}
            if(frame_flags&1) {
                Vector3 r=right*size,u=up*size;
                if(flags&1048576){r=Vector3(1,0,0).rotated(Vector3(0,1,0),p.angle)*size;u=Vector3(0,0,-1).rotated(Vector3(0,1,0),p.angle)*size;}
                quad(pos-r+u,pos-r-u,pos+r+u,pos+r-u,single_tile?Rect2(0,0,1,1):uv_at(heads[segment],blend),color);
            }
            if(frame_flags&2) {
                Vector3 end=pos-velocity*tail_length,side=velocity.cross(eye-pos).normalized()*size;
                quad(pos+side,pos-side,end+side,end-side,single_tile?Rect2(0,0,1,1):uv_at(tails[segment],blend),color);
            }
        }
    }
    void draw_particles(const Array &particles,const Dictionary &source,Transform3D transform,Color tint,double alpha,Vector3 right,Vector3 up,Vector3 eye) {
        draw_particle_values(particles.size(),[&](int i){Dictionary p=particles[i];return ParticleValue{p[pos_key],p[velocity_key],p[age_key],p[angle_key],p[scale_key]};},source,transform,tint,alpha,right,up,eye);
    }
    void draw_packed_particles(const PackedFloat64Array &particles,const Dictionary &source,Transform3D transform,Color tint,double alpha,Vector3 right,Vector3 up,Vector3 eye) {
        const double *p=particles.ptr();
        draw_particle_values(particles.size()/10,[&](int i){int j=i*10;return ParticleValue{Vector3(p[j],p[j+1],p[j+2]),Vector3(p[j+3],p[j+4],p[j+5]),p[j+6],p[j+7],p[j+8]};},source,transform,tint,alpha,right,up,eye);
    }
    Array geometry_arrays() const {
        PackedVector3Array packed_vertices;PackedColorArray packed_colors;PackedVector2Array packed_uvs;PackedInt32Array packed_indices;
        packed_vertices.resize(vertices.size());packed_colors.resize(colors.size());packed_uvs.resize(uvs.size());packed_indices.resize(indices.size());
        if(!vertices.empty())std::copy(vertices.begin(),vertices.end(),packed_vertices.ptrw());
        if(!colors.empty())std::copy(colors.begin(),colors.end(),packed_colors.ptrw());
        if(!uvs.empty())std::copy(uvs.begin(),uvs.end(),packed_uvs.ptrw());
        if(!indices.empty())std::copy(indices.begin(),indices.end(),packed_indices.ptrw());
        Array result;result.resize(Mesh::ARRAY_MAX);result[Mesh::ARRAY_VERTEX]=packed_vertices;result[Mesh::ARRAY_COLOR]=packed_colors;result[Mesh::ARRAY_TEX_UV]=packed_uvs;result[Mesh::ARRAY_INDEX]=packed_indices;return result;
    }
};
void initialize_banjo(ModuleInitializationLevel level){if(level==MODULE_INITIALIZATION_LEVEL_SCENE)ClassDB::register_class<BanjoAccelerator>();}
void uninitialize_banjo(ModuleInitializationLevel){}
extern "C" GDExtensionBool GDE_EXPORT banjo_library_init(GDExtensionInterfaceGetProcAddress address,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(address,library,initialization);
    init.register_initializer(initialize_banjo);init.register_terminator(uninitialize_banjo);init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);return init.init();
}
