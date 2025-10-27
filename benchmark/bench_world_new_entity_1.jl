
function setup_world_new_entity_1(n::Int)
    world = ECSManager(Position, Velocity)

    # Run once to allocate memory
    entities = Vector{Entity}()
    for _ in 1:n
        e = create_entity!(world, (;Position=Position(0, 0),))
        push!(entities, e)
    end

    for e in entities
        remove_entity!(world, e)
    end

    return world
end

function benchmark_world_new_entity_1(args, n::Int)
    world = args
    request_entity!(world, (;Position=Position(0, 0),), n)
end

for n in (100, 1_000, 10_000, 100_000)
    SUITE["benchmark_world_new_entity_1 n=$n"] = @be setup_world_new_entity_1($n) benchmark_world_new_entity_1(_, $n) seconds = SECONDS
end
