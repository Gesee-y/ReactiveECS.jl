
function setup_world_add_remove(n_entities::Int)
    world = ECSManager(Position, Velocity, CompA, CompB, CompC)

    pos, vel = get_component(world, :Position), get_component(world, :Velocity)
    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2))))
    end

    for e in entities
        attach_component(world, e, Velocity(0,0), CompA(0,0), CompB(0,0), CompC(0,0))
        detach_component(world, e, :Velocity, :CompA, :CompB, :CompC)
    end

    return (world, entities)
end

function benchmark_world_add_remove(args, n)
    world, ents= args
    attach_component(world, ents, Velocity(0,0), CompA(0,0), CompB(0,0), CompC(0,0))
    detach_component(world, ents, :Velocity, :CompA, :CompB, :CompC)    
end

for n in (100, 1_000, 10_000, 100_000)
    SUITE["benchmark_world_add_remove_large n=$n"] = @be setup_world_add_remove($n) benchmark_world_add_remove(_, $n) seconds = SECONDS
end
