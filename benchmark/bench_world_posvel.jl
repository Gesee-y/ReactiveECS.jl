
function setup_world_posvel(n_entities::Int)
    world = ECSManager()
    register_component!(world, Position)
    register_component!(world, Velocity)

    pos, vel = get_component(world, :Position), get_component(world, :Velocity)

    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2), Velocity=Velocity(1,1))))
    end

    ids = getindex.(get_id.(entities))

    return (get_iterator(getdata(pos), ids), get_iterator(getdata(vel), ids))
end

function benchmark_world_posvel(args, n)
    positions, velocities = args
    
    for i in eachindex(positions)
        pblock, ids = positions[i]
        vblock = velocities[i][1]
        for j in ids
            pos = pblock[j]
            vel = vblock[j]
            pblock[j] = Position(pos.x+vel.dx, pos.y+vel.dy)
        end
    end
end

for n in (100, 1_000, 10_000, 100_000)
    SUITE["benchmark_world_posvel n=$n"] = @be setup_world_posvel($n) benchmark_world_posvel(_, n) seconds = SECONDS
end
