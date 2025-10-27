
function setup_world_new_entity_5(n::Int)
    world = ECSManager(Position, Velocity, CompA, CompB, CompC)

    # Run once to allocate memory
    entities = Vector{Entity}()
    for _ in 1:n
        push!(entities, create_entity!(world, (; Position=Position(0, 0), Velocity=Velocity(0, 0), CompA=CompA(0, 0), 
            CompB=CompB(0, 0), CompC=CompC(0, 0))))
    end

    for e in entities
        remove_entity!(world, e)
    end

    return world
end

function benchmark_world_new_entity_5(args, n::Int)
    world = args
    request_entity!(world, (; Position=Position(0, 0), Velocity=Velocity(0, 0), CompA=CompA(0, 0), 
        CompB=CompB(0, 0), CompC=CompC(0, 0)), n)
end

for n in (100, 1_000, 10_000, 100_000)
    SUITE["benchmark_world_new_entity_5 n=$n"] = @be setup_world_new_entity_5($n) benchmark_world_new_entity_5(_, $n) seconds = SECONDS
end
