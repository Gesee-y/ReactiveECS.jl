
function setup_world_get_1(n_entities::Int)
    world = ECSManager()
    register_component!(world, Position)

    pos = get_component(world, :Position)
    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2))))
    end

    return (entities, pos)
end

function benchmark_world_get_1(args, n)
    entities, pos_column = args
    x = pos_column.x
    sum = 0.0
    @inbounds for e in entities
        i = get_id(e)[]
        sum += x[i]
    end
end

for n in (100, 1_000, 10_000, 100_000)
    SUITE["benchmark_world_get_1 n=$n"] = @be setup_world_get_1($n) benchmark_world_get_1(_, $n) seconds = SECONDS
end
