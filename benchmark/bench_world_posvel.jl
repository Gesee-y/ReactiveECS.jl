
function setup_world_posvel(n_entities::Int)
    world = ECSManager()
    register_component!(world, Position)
    register_component!(world, Velocity)

    pos, vel = get_component(world, :Position), get_component(world, :Velocity)

    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2))))
    end

    return (entities, pos, vel)
end

function benchmark_world_posvel(args, n)
    entities, pos_column, vel_column = args
    x = pos_column.x
    y = pos_column.y
    dx = vel_column.dx
    dy = vel_column.dy
    @inbounds for e in entities
        i = get_id(e)[]
        x[i] += dx[i]
        y[i] += dy[i]
    end
end

for n in (100, 1_000, 10_000, 100_000)
    SUITE["benchmark_world_posvel n=$n"] = @be setup_world_posvel($n) benchmark_world_posvel(_, n) seconds = SECONDS
end
