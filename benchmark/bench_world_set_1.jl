
function setup_world_set_1(n_entities::Int)
    world = ECSManager(Position, Velocity)

    pos = get_component(world, :Position)
    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2))))
    end

    return (getindex.(get_id.(entities)), pos)
end

function benchmark_world_set_1(args, n)
    ids, pos = args
    for i in ids
        pos[i] = Position(1, 2)
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_set_1 n=$n"] = @be setup_world_set_1($n) benchmark_world_set_1(_, $n) seconds = SECONDS
end
