
function setup_world_add_remove(n_entities::Int)
    world = ECSManager()
    register_component!(world, Position)
    register_component!(world, Velocity)

    pos, vel = get_component(world, :Position), get_component(world, :Velocity)
    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2))))
    end

    for e in entities
        attach_component(world, e, Velocity(0,0))
        detach_component(world, e, :Velocity)
    end

    return (world, entities)
end

function benchmark_world_add_remove(args, n)
    world, ents= args
    attach_component(world, ents, Velocity(0,0))
    detach_component(world, ents, :Velocity)
end

for n in (100, 1_000, 10_000, 100_000)
    SUITE["benchmark_world_add_remove n=$n"] = @be setup_world_add_remove($n) benchmark_world_add_remove(_, $n) seconds = SECONDS
end
