using EDECS

# Component definitions
struct Health <: AbstractComponent
    hp::Int
end
EDECS.get_bits(::Type{Health})::UInt128 = 0b1

mutable struct TransformComponent <: AbstractComponent
    x::Float32
    y::Float32
end
EDECS.get_bits(::Type{TransformComponent})::UInt128 = 0b10

struct PhysicComponent <: AbstractComponent
    velocity::Float32
end
EDECS.get_bits(::Type{PhysicComponent})::UInt128 = 0b100

# Naming helper for components
EDECS.get_name(::TransformComponent) = :Transform
EDECS.get_name(::PhysicComponent)    = :Physic

# System declarations via macro
@system(PhysicSystem, Entity)
@system(PrintSystem, Entity)
@system(RenderSystem, Entity)

# System behavior implementations
function run!(::PhysicSystem, ref::WeakRef)
    entities = ref.value # Getting the array of entities for the Weak reference
    for i in eachindex(entities)
        entity = validate(ref, i) # We check that the entity is valid
        t = get_component(entity, TransformComponent)
        v = get_component(entity, PhysicComponent)
        t.x += v.velocity
    end

    return ref
end

function run!(sys::PrintSystem, ref::WeakRef)
    entities = ref.value
    for i in eachindex(entities)
        entity = validate(ref, i)
	id = entity.id
	println("Entity: $id")
    end
end

function run!(::RenderSystem, ref)
    entities = ref.value
    for i in eachindex(entities)
	entity = validate(ref, i)
        t = get_component(entity, TransformComponent)
        println("Rendering entity $(entity.id) at position ($(t.x), $(t.y))")
    end
end


# ECS manager initialization
ecs = ECSManager{Entity}()

# Create two entities
e1 = Entity(1; Health = Health(100), Transform = TransformComponent(1.0,2.0))
e2 = Entity(2; Health = Health(50), Transform = TransformComponent(-5.0,0.0), Physic = PhysicComponent(1.0))

add_entity!(ecs, e1)
add_entity!(ecs, e2)

# System instances
print_sys   = PrintSystem()
physic_sys  = PhysicSystem()
render_sys  = RenderSystem()

# Subscribe to archetypes
subscribe!(ecs, print_sys,   (:Health, :Transform))
subscribe!(ecs, physic_sys,  (:Transform, :Physic))
listen_to(physic_sys, render_sys) # This function tells physic system that he should dispatch the results of his process to his listeners

# Launch systems (asynchronous task)
run_system!(print_sys)
run_system!(physic_sys)
run_system!(render_sys)

# Simulate 3 frames
for i in 1:3
    println("FRAME $i")
    dispatch_data(ecs)
    yield()
end
