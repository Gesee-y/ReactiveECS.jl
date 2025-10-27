
function setup_world_get_5(n_entities::Int)
    world = ECSManager(Position, Velocity, CompA, CompB, CompC)

    pos, vel, A, B, C = (get_component(world, :Position), get_component(world, :Velocity), get_component(world, :CompA), 
        get_component(world, :CompB), get_component(world, :CompC))
    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i * 2), Velocity=Velocity(0, 0), CompA=CompA(0, 0), 
            CompB=CompB(0, 0), CompC=CompC(0, 0))))
    end

    return (entities, pos, vel, A, B, C)
end

function benchmark_world_get_5(args, n)
    entities, position, velocity, A, B, C = args
    sum = 0.0
    @inbounds for e in entities
        i = get_id(e)[]
        pos, vel, a, b, c = position[i], velocity[i], A[i], B[i], C[i]
        sum += pos.x + vel.dx + a.x + b.x + c.x
    end
end

for n in (100, 1_000, 10_000, 100_000)
    SUITE["benchmark_world_get_5 n=$n"] = @be setup_world_get_5($n) benchmark_world_get_5(_, $n) seconds = SECONDS
end
