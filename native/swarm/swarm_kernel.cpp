#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/box_shape3d.hpp>
#include <godot_cpp/classes/sphere_shape3d.hpp>
#include <godot_cpp/classes/cylinder_shape3d.hpp>
#include <godot_cpp/classes/convex_polygon_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/physics_test_motion_parameters3d.hpp>
#include <godot_cpp/classes/physics_test_motion_result3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <vector>

using namespace godot;

class HDSwarmKernel : public RefCounted {
    GDCLASS(HDSwarmKernel, RefCounted);
    struct Names {
        const StringName _dynamic{"_dynamic"};
        const StringName _fixed_clear{"_fixed_clear"};
        const StringName _ground_moved{"_ground_moved"};
        const StringName _ground_real_velocity{"_ground_real_velocity"};
        const StringName _look{"_look"};
        const StringName _push_remaining{"_push_remaining"};
        const StringName _route{"_route"};
        const StringName _route_clock{"_route_clock"};
        const StringName _waypoint{"_waypoint"};
        const StringName _yield_side{"_yield_side"};
        const StringName body_radius{"body_radius"};
        const StringName can_walk_direct{"can_walk_direct"};
        const StringName chase_route{"chase_route"};
        const StringName combat_stop_distance{"combat_stop_distance"};
        const StringName contact_distance{"contact_distance"};
        const StringName crowd_clearance_distance{"crowd_clearance_distance"};
        const StringName data{"data"};
        const StringName effective_move_speed{"effective_move_speed"};
        const StringName enabled{"enabled"};
        const StringName flat_ground_height{"flat_ground_height"};
        const StringName gravity{"gravity"};
        const StringName ground_collision_body{"ground_collision_body"};
        const StringName ground_movement_enabled{"ground_movement_enabled"};
        const StringName ground_position{"ground_position"};
        const StringName navigation{"navigation"};
        const StringName obstacle_certificates_enabled{"obstacle_certificates_enabled"};
        const StringName obstacle_field{"obstacle_field"};
        const StringName pursuit_flank_strength{"pursuit_flank_strength"};
        const StringName pursuit_lookahead{"pursuit_lookahead"};
        const StringName route_interval{"route_interval"};
        const StringName separation{"separation"};
        const StringName separation_radius{"separation_radius"};
        const StringName separation_strength{"separation_strength"};
        const StringName spatial_index{"spatial_index"};
        const StringName target{"target"};
        const StringName terrain{"terrain"};
    } keys;
    const NodePath collision_path{"Collision"};
    std::vector<int32_t> pairs;
    PackedVector3Array reference;
    int64_t revision = -1;
    double cell_size = 0;
    Ref<PhysicsTestMotionParameters3D> parameters;
    Ref<PhysicsTestMotionResult3D> result;
    RID floor_rid;
    int64_t native_moves = 0, certified_moves = 0, fallback_moves = 0, direct_moves = 0;
    bool diagnostics_enabled = false;
    int64_t chase_ns = 0, ground_ns = 0, proof_ns = 0, plan_ns = 0;
    struct Timing {
        bool active;
        int64_t &total;
        std::chrono::steady_clock::time_point start;
        Timing(bool enabled,int64_t &destination):active(enabled),total(destination) { if(active)start=std::chrono::steady_clock::now(); }
        ~Timing() { if(active)total+=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-start).count(); }
    };
    static double horizontal(const Vector3 &a, const Vector3 &b) {
        return Vector2(a.x - b.x, a.z - b.z).length();
    }
    static double num(Object *o, const StringName &key) { return double(o->get(key)); }
    static bool flag(Object *o, const StringName &key) { return bool(o->get(key)); }
    static Vector3 pair_force(Vector3 offset, double spacing, double contact, int64_t a, int64_t b) {
        if (std::abs(double(offset.y)) > std::max(contact, 0.35)) return Vector3();
        offset.y = 0;
        const double distance = offset.length();
        if (distance >= spacing) return Vector3();
        Vector3 direction;
        if (distance > 0.00001) direction = offset / real_t(distance);
        else {
            const uint64_t seed = uint64_t(std::min(a,b)) ^ (uint64_t(std::max(a,b)) << 1);
            const double angle = double(seed % 4096) * 6.283185307179586476925286766559 / 4096.0;
            direction = Vector3(real_t(std::cos(angle)), 0, real_t(std::sin(angle))) * (a < b ? 1.0f : -1.0f);
        }
        const double skin = std::max(spacing * 0.1, 0.02);
        return direction * real_t(spacing - distance) / real_t(std::max(distance - contact + skin, skin));
    }
    static AABB shape_bounds(const Ref<Shape3D> &shape, const Transform3D &transform) {
        if (shape.is_null()) return AABB(Vector3(INFINITY,0,0),Vector3());
        AABB local;
        if (Ref<BoxShape3D> s = shape; s.is_valid()) local = AABB(-s->get_size()*0.5f,s->get_size());
        else if (Ref<SphereShape3D> s = shape; s.is_valid()) {
            const Vector3 half(s->get_radius(),s->get_radius(),s->get_radius()); local = AABB(-half,half*2);
        } else if (Ref<CapsuleShape3D> s = shape; s.is_valid()) {
            const Vector3 half(s->get_radius(),s->get_height()*0.5,s->get_radius()); local = AABB(-half,half*2);
        } else if (Ref<CylinderShape3D> s = shape; s.is_valid()) {
            const Vector3 half(s->get_radius(),s->get_height()*0.5,s->get_radius()); local = AABB(-half,half*2);
        } else {
            PackedVector3Array points;
            if (Ref<ConvexPolygonShape3D> s = shape; s.is_valid()) points = s->get_points();
            else if (Ref<ConcavePolygonShape3D> s = shape; s.is_valid()) points = s->get_faces();
            if (points.is_empty()) return AABB(Vector3(INFINITY,0,0),Vector3());
            local = AABB(points[0],Vector3());
            for (int i=0;i<points.size();++i) local.expand_to(points[i]);
        }
        const Basis &basis = transform.basis;
        if (basis != Basis()) {
            const Vector3 scale(basis.get_column(0).length(),basis.get_column(1).length(),basis.get_column(2).length());
            if (std::min({scale.x,scale.y,scale.z}) <= 0) return AABB(Vector3(INFINITY,0,0),Vector3());
            const Basis axes(basis.get_column(0)/scale.x,basis.get_column(1)/scale.y,basis.get_column(2)/scale.z);
            if (!axes.is_equal_approx(axes.orthonormalized())) return AABB(Vector3(INFINITY,0,0),Vector3());
            if ((Ref<CapsuleShape3D>(shape).is_valid() || Ref<SphereShape3D>(shape).is_valid() || Ref<CylinderShape3D>(shape).is_valid()) &&
                (!Math::is_equal_approx(scale.x,scale.y) || !Math::is_equal_approx(scale.x,scale.z))) return AABB(Vector3(INFINITY,0,0),Vector3());
        }
        return transform.xform(local.grow(shape->get_margin())).grow(0.01f);
    }
    bool clear_body(CharacterBody3D *body, PhysicsBody3D *support, Object *field, const Vector3 &motion) {
        Timing timing(diagnostics_enabled,proof_ns);
        auto *collider = Object::cast_to<CollisionShape3D>(body->get_node_or_null(collision_path));
        if (!collider || collider->is_disabled() || Ref<CapsuleShape3D>(collider->get_shape()).is_null()) return false;
        const AABB start = shape_bounds(collider->get_shape(),collider->get_global_transform());
        if (!start.position.is_finite()) return false;
        const AABB swept = start.merge(AABB(start.position + motion,start.size)).grow(body->get_safe_margin());
        const int64_t mask = body->get_collision_mask();
        // Existing synchronous invalidation/managed bindings remain authoritative.
        if (!bool(field->call(keys._fixed_clear,swept,mask))) return false;
        const PackedInt32Array owners = body->get_shape_owners();
        if (owners.size()!=1 || body->shape_owner_get_shape_count(owners[0])!=1 ||
            body->shape_owner_get_owner(owners[0])!=collider || body->shape_owner_get_shape(owners[0],0)!=collider->get_shape() ||
            body->shape_owner_get_transform(owners[0])!=collider->get_transform()) return false;
        const Dictionary dynamic = field->get(keys._dynamic);
        const Array bodies = dynamic.keys();
        for (int i=0;i<bodies.size();++i) {
            auto *other = Object::cast_to<PhysicsBody3D>(bodies[i]);
            if (!other || other==body || other==support || (other->get_collision_layer() & mask)==0) continue;
            const Transform3D live = PhysicsServer3D::get_singleton()->body_get_state(other->get_rid(),PhysicsServer3D::BODY_STATE_TRANSFORM);
            const PackedInt32Array shape_owners = other->get_shape_owners();
            for (int owner:shape_owners) {
                const Transform3D shape_transform = live * other->shape_owner_get_transform(owner);
                for (int j=0;j<other->shape_owner_get_shape_count(owner);++j) {
                    const AABB bounds = shape_bounds(other->shape_owner_get_shape(owner,j),shape_transform);
                    if (!bounds.position.is_finite() || bounds.intersects(swept)) return false;
                }
            }
        }
        return true;
    }
    bool flat_move(CharacterBody3D *body, Object *path, double delta, double radius) {
        Timing timing(diagnostics_enabled,ground_ns);
        const Transform3D start = body->get_global_transform();
        const Vector3 velocity = body->get_velocity();
        Vector3 motion = Vector3(velocity.x,0,velocity.z) * real_t(delta);
        const double width = radius + body->get_safe_margin();
        const double floor_y = path->call(keys.flat_ground_height,start.origin,start.origin+motion,width);
        if (std::isnan(floor_y) || start.origin.y < floor_y-body->get_safe_margin() || start.origin.y > floor_y+std::max(0.0025,double(body->get_safe_margin())*2.0)) return false;
        Object *terrain = path->get(keys.terrain);
        auto *support = Object::cast_to<PhysicsBody3D>(terrain->call(keys.ground_collision_body));
        if (!support || (body->get_collision_mask() & support->get_collision_layer())==0) return false;
        const RID rid = support->get_rid();
        if (rid!=floor_rid) { floor_rid=rid; TypedArray<RID> excluded; excluded.push_back(rid); parameters->set_exclude_bodies(excluded); }
        if (flag(terrain,keys.obstacle_certificates_enabled)) {
            Object *field = terrain->call(keys.obstacle_field);
            if (field && flag(field,keys.enabled) && clear_body(body,support,field,motion)) {
                body->set_global_position(start.origin+motion);
                body->set_velocity(Vector3(velocity.x,0,velocity.z));
                ++certified_moves; return true;
            }
        }
        parameters->set_margin(body->get_safe_margin());
        parameters->set_recovery_as_collision_enabled(true);
        Transform3D transform = start;
        Vector3 speed(velocity.x,0,velocity.z);
        for (int slide=0;slide<body->get_max_slides();++slide) {
            parameters->set_from(transform); parameters->set_motion(motion);
            const bool hit = PhysicsServer3D::get_singleton()->body_test_motion(body->get_rid(),parameters,result);
            const Vector3 travel = result->get_travel();
            if (std::abs(double(travel.y))>0.00001) return false;
            const Vector3 next = transform.origin+travel;
            if (travel!=motion && double(path->call(keys.flat_ground_height,transform.origin,next,width))!=floor_y) return false;
            transform.origin=next;
            if (!hit) break;
            const Vector3 normal = result->get_collision_normal();
            if (std::abs(double(normal.y))>0.01) return false;
            motion=result->get_remainder().slide(normal); speed=speed.slide(normal);
            if (motion.is_zero_approx()) break;
            if (double(path->call(keys.flat_ground_height,transform.origin,transform.origin+motion,width))!=floor_y) return false;
        }
        body->set_global_transform(transform); body->set_velocity(speed); return true;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("plan","cells","positions","ids","active","spacing","bodies","cell_size","revision"),&HDSwarmKernel::plan);
        ClassDB::bind_method(D_METHOD("clear"),&HDSwarmKernel::clear);
        ClassDB::bind_method(D_METHOD("move_chase","body","path","index","target","route","input","look","speed","clearance","delta","stop"),&HDSwarmKernel::move_chase);
        ClassDB::bind_method(D_METHOD("move_body","body","path","delta","radius"),&HDSwarmKernel::move_body);
        ClassDB::bind_method(D_METHOD("get_metrics"),&HDSwarmKernel::get_metrics);
        ClassDB::bind_method(D_METHOD("set_diagnostics_enabled","enabled"),&HDSwarmKernel::set_diagnostics_enabled);
        ClassDB::bind_method(D_METHOD("is_diagnostics_enabled"),&HDSwarmKernel::is_diagnostics_enabled);
        ADD_PROPERTY(PropertyInfo(Variant::BOOL,"diagnostics_enabled"),"set_diagnostics_enabled","is_diagnostics_enabled");
    }
public:
    HDSwarmKernel() { parameters.instantiate(); result.instantiate(); }
    void clear() { pairs.clear(); reference.clear(); revision=-1; }
    void set_diagnostics_enabled(bool value) { diagnostics_enabled=value; }
    bool is_diagnostics_enabled() const {return diagnostics_enabled;}
    Dictionary get_metrics() const {
        Dictionary d; d["native_moves"]=native_moves; d["certified_moves"]=certified_moves; d["fallback_moves"]=fallback_moves; d["direct_moves"]=direct_moves;
        d["chase_us"]=double(chase_ns)/1000;d["ground_us"]=double(ground_ns)/1000;d["proof_us"]=double(proof_ns)/1000;d["plan_us"]=double(plan_ns)/1000;
        return d;
    }
    bool move_body(CharacterBody3D *body,Object *path,double delta,double radius) {
        if(!body || !path || !std::isfinite(delta) || delta<=0 || !std::isfinite(radius) || radius<0)return false;
        ++direct_moves;
        return flat_move(body,path,delta,radius);
    }
    PackedVector3Array plan(const Dictionary &cells,const PackedVector3Array &positions,const PackedInt64Array &ids,
        const PackedByteArray &active,const PackedFloat64Array &spacing,const PackedFloat64Array &bodies,double size,int64_t rev) {
        Timing timing(diagnostics_enabled,plan_ns);
        if (positions.size()>INT32_MAX) return PackedVector3Array();
        const int count=int(positions.size());
        if (ids.size()!=count || active.size()!=count || spacing.size()!=count || bodies.size()!=count || !std::isfinite(size) || size<=0) return PackedVector3Array();
        for (int i=0;i<count;++i) {
            if (!positions[i].is_finite() || !std::isfinite(spacing[i]) || !std::isfinite(bodies[i]) || spacing[i]<0 || bodies[i]<0) {clear();return PackedVector3Array();}
        }
        bool reuse=rev>=0 && rev==revision && size==cell_size && count==reference.size();
        if (reuse) for (int i=0;i<count;++i) {
            if (!active[i]) continue;
            const Vector3 moved=positions[i]-reference[i];
            if (double(moved.x)*moved.x+double(moved.z)*moved.z>=0.3*0.3*0.25) {reuse=false;break;}
        }
        if (!reuse) {
            pairs.clear(); double maximum=0;
            for(int i=0;i<count;++i) if(active[i]) maximum=std::max(maximum,spacing[i]);
            const double buffer=0.3+0.00001;
            if ((maximum+buffer)/size>1024) {clear();return PackedVector3Array();}
            const int reach=int(std::ceil((maximum+buffer)/size));
            const Array cell_keys=cells.keys();
            for(int k=0;maximum>0 && k<cell_keys.size();++k) {
                if (cell_keys[k].get_type()!=Variant::VECTOR2I) {clear();return PackedVector3Array();}
                const Vector2i key=cell_keys[k]; const Array own=cells[key];
                for(int dz=0;dz<=reach;++dz) for(int dx=dz==0?0:-reach;dx<=reach;++dx) {
                    const Array other=cells.get(key+Vector2i(dx,dz),Array());
                    const bool same=dx==0 && dz==0;
                    for(int ia=0;ia<own.size();++ia) {
                        const int64_t a_value=own[ia];
                        if(a_value<0 || a_value>=count) {clear();return PackedVector3Array();}
                        const int a=int(a_value); if(!active[a])continue;
                        for(int ib=same?ia+1:0;ib<other.size();++ib) {
                            const int64_t b_value=other[ib];
                            if(b_value<0 || b_value>=count) {clear();return PackedVector3Array();}
                            const int b=int(b_value); if(!active[b])continue;
                            const Vector3 offset=positions[a]-positions[b];
                            const double distance=(spacing[a]+spacing[b])*0.5+buffer;
                            if(double(offset.x)*offset.x+double(offset.z)*offset.z<distance*distance) {pairs.push_back(a);pairs.push_back(b);}
                        }
                    }
                }
            }
            reference=positions.duplicate();revision=rev;cell_size=size;
        }
        PackedVector3Array forces; forces.resize(count); Vector3 *out=forces.ptrw();
        for(size_t i=0;i<pairs.size();i+=2) {
            const int a=pairs[i],b=pairs[i+1]; const Vector3 offset=positions[a]-positions[b];
            const double distance=(spacing[a]+spacing[b])*0.5;
            if(double(offset.x)*offset.x+double(offset.z)*offset.z>=distance*distance)continue;
            const Vector3 force=pair_force(offset,distance,bodies[a]+bodies[b],ids[a],ids[b]);
            out[a]+=force;out[b]-=force;
        }
        return forces;
    }
    bool move_chase(CharacterBody3D *body,Object *path,Object *index,Node3D *target,PackedVector3Array route,
        const PackedFloat64Array &input,const Vector3 &look,double speed,double clearance,double delta,double base_stop) {
        Timing timing(diagnostics_enabled,chase_ns);
        if (!body || !body->is_inside_tree() || !target || !path || !index || input.size()!=15 || !std::isfinite(delta) || delta<=0 || !std::isfinite(speed) || !std::isfinite(clearance) || !std::isfinite(base_stop) || !look.is_finite()) return false;
        for (int i=0;i<input.size();++i) if (!std::isfinite(input[i])) return false;
        if (input[4]<0 || input[5]<0 || input[2]<0 || (!route.is_empty() && input[2]>=route.size())) return false;
        const Vector3 origin=body->get_global_position(),goal=target->get_global_position();
        Vector3 away=origin-goal;away.y=0;
        const double target_distance=horizontal(origin,goal);
        double stop=base_stop;
        if(clearance>0) {
            stop+=clearance;
            if(base_stop<input[7])stop=std::min(stop,std::max(base_stop,input[7]-0.05));
        }
        Vector3 direction;
        if(target_distance>stop) {
            double clock=input[0]-delta;
            int waypoint=int(input[2]);
            if(clock<=0) {clock=input[1];route=path->call(keys.chase_route,origin,goal,input[11]);waypoint=route.size()>1?1:0;body->set(keys._route,route);}
            body->set(keys._route_clock,clock);
            if(!route.is_empty() && horizontal(origin,route[route.size()-1])>0.1) {
                while(waypoint<route.size()-1 && horizontal(origin,route[waypoint])<0.14)++waypoint;
                direction=route[waypoint]-origin;direction.y=0;direction.normalize();
            }
            body->set(keys._waypoint,waypoint);
        }
        const Vector3 intended=direction;
        const double strength=input[9],radius=input[4],spacing=input[8];
        if(spacing>0 && strength>0) {
            const Vector3 separation=index->call(keys.separation,body,spacing);
            direction=(direction+separation*real_t(strength)).limit_length(1);
        }
        const double flank=input[10];
        if(!intended.is_zero_approx() && flank>0 && strength>0) {
            const double pressure=std::clamp(1.0-double(direction.dot(intended)),0.0,1.0);
            double side_value=input[3];
            if(pressure<0.35)side_value=0;
            else {
                const double space=std::max(spacing,radius*2.1), combat_stop=input[6];
                const double approach=Math::smoothstep(combat_stop+space*0.3,combat_stop+space*1.5,target_distance);
                const double amount=flank*pressure*approach;
                if(amount<0.02)side_value=0;
                else {
                    const Vector3 side=Vector3(0,1,0).cross(intended);
                    if(side_value==0) {
                        const double lateral=direction.dot(side);
                        side_value=std::abs(lateral)>0.08?(lateral>0?1:-1):((UtilityFunctions::hash(int64_t(body->get_instance_id()))%2)==0?1:-1);
                    }
                    for(double choice:{side_value,-side_value}) {
                        const Vector3 candidate=(direction+side*real_t(choice)*real_t(amount)).limit_length(1);
                        const Vector3 next=origin+candidate*real_t(std::max(0.35,radius));
                        Object *data=path->get(keys.data);
                        if(data && !bool(path->call(keys.can_walk_direct,origin,path->call(keys.ground_position,next))))continue;
                        side_value=choice;direction=candidate;break;
                    }
                }
            }
            body->set(keys._yield_side,side_value);
        }
        if(clearance>0) {
            away=target_distance>0.00001?away/real_t(target_distance):-look.normalized();
            const double required=std::clamp((stop-target_distance)/(std::max(speed,0.01)*0.12),-1.0,1.0);
            const double radial=direction.dot(away);
            if(radial<required)direction+=away*real_t(required-radial);
            direction=direction.limit_length(1);
        }
        Vector3 velocity=body->get_velocity();
        const double gravity=input[5];
        velocity.y=(input[13]!=0 || body->is_on_floor())?0:real_t(double(velocity.y)-gravity*delta);
        velocity.x=real_t(double(direction.x)*speed);velocity.z=real_t(double(direction.z)*speed);
        body->set_velocity(velocity); body->set(keys._ground_moved,false);
        bool grounded=false;
        if(input[12]!=0 && body->get_global_basis()==Basis() && body->get_up_direction()==Vector3(0,1,0) &&
           body->get_motion_mode()==CharacterBody3D::MOTION_MODE_GROUNDED && input[14]<=0 && velocity.y<=0 && velocity.y>=-gravity*delta*1.01)
            grounded=flat_move(body,path,delta,radius);
        Vector3 real_velocity;
        if(grounded) {
            real_velocity=(body->get_global_position()-origin)/real_t(delta);
            body->set(keys._ground_moved,true);body->set(keys._ground_real_velocity,real_velocity);++native_moves;
        } else {body->move_and_slide();real_velocity=body->get_real_velocity();++fallback_moves;}
        Vector3 heading=intended.normalized();
        if(heading.is_zero_approx() || real_velocity.dot(heading)<0.15) {heading=target->get_global_position()-body->get_global_position();heading.y=0;}
        if(!heading.is_zero_approx())body->set(keys._look,heading.normalized());
        return true;
    }
};

static void initialize_swarm(ModuleInitializationLevel level) { if(level==MODULE_INITIALIZATION_LEVEL_SCENE) GDREGISTER_CLASS(HDSwarmKernel); }
static void terminate_swarm(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT hd2d_swarm_init(GDExtensionInterfaceGetProcAddress address,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject object(address,library,initialization);
    object.register_initializer(initialize_swarm);object.register_terminator(terminate_swarm);
    object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return object.init();
}
