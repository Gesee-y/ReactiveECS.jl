include("..\\src\\EDECS.jl")

struct Health <: AbstractComponent
	hp::Int
end

mutable struct TransformComponent <: AbstractComponent
    x::Float32
    y::Float32
end

struct PhysicComponent <: AbstractComponent
    velocity::Float32
end

get_name(::TransformComponent) = :Transform
get_name(::PhysicComponent) = :Physic

@system(PhysicSystem, Entity)
@system(PrintSystem, Entity)
@system(RenderSystem, Entity)

function run!(::PhysicSystem, entities)
	for entity in entities
	    t = entity.components[:Transform]
	    v = entity.components[:Physic]
	    t.x += v.velocity
    end
end

function run!(sys::PrintSystem, entities)
	for entity in entities
		id = entity.id
		println("Entity: $id")
	end
end

function run!(::RenderSystem, entities)
    for entity in entities
	    t = entity.components[:Transform]
	    println("Rendering entity $(entity.id) at position ($(t.x), $(t.y))")
	end
end

ecs = ECSManager{Entity}()
e = Entity(1, Dict(:Health => Health(100), :Transform => TransformComponent(1.0,2.0)))
e2 = Entity(2, Dict(:Health => Health(50), :Transform => TransformComponent(-5.0,0.0), :Physic => PhysicComponent(1.0)))

add_entity!(ecs, e)
add_entity!(ecs, e2)

for i in 1:1024
	add_entity!(ecs,Entity(i+2, Dict(:Health => Health(50), :Transform => TransformComponent(-5.0+i,0.0), :Physic => PhysicComponent(1.0))))
end

print_sys = PrintSystem()
physic_sys = PhysicSystem()
render_sys = RenderSystem()

subscribe!(ecs, print_sys, (:Health, :Transform))
subscribe!(ecs, physic_sys, (:Transform, :Physic))
subscribe!(ecs, render_sys, (:Transform,))

run_system!(print_sys)
run_system!(physic_sys)
run_system!(render_sys)

for i in 1:3
	println("FRAME $i")
	@time dispatch_data(ecs)
	yield()
end
sleep(2)

#=
    ajouter un systeme : 0.000147 seconds (26 allocations: 1.875 KiB)
    creer un ecs manager : 0.000035 seconds (17 allocations: 2.062 KiB)
    creer une entite : 0.000039 seconds (17 allocations: 1.656 KiB)
    ajouter une entite : 0.000036 seconds (9 allocations: 400 bytes)
    creer une instance de systeme :0.000025 seconds (15 allocations: 672 bytes) (fait une seule fois)
    souscrire a un archetype : 0.079826 seconds (13.04 k allocations: 961.953 KiB, 99.90% compilation time)( fait une seule fois)
    lancer un systeme : 0.016844 seconds (3.53 k allocations: 253.867 KiB, 99.61% compilation time) (fait une seule fois)
    dispatcher les evenement : 0.000031 seconds (6 allocations: 288 bytes) (fait a chaque frame pour update)
=#