
function setup_world_set_1(n_entities::Int)
    world = ECSManager(Position, Velocity)

    pos = get_component(world, :Position)
    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2))))
    end

    ids = getindex.(get_id.(entities))

    return get_iterator(getdata(pos), ids)
end

function benchmark_world_set_1(args, n)
    pos_iter = args
    for (pos_block, ids) in pos_iter
        x,y = pos_block.x, pos_block.y
        @inbounds for i in ids
            x[i], y[i] = (1,2)
        end
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_set_1_iter n=$n"] = @be setup_world_set_1($n) benchmark_world_set_1(_, $n) seconds = SECONDS
end
