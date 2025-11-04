
function setup_world_set_5(n_entities::Int)
    world = ECSManager(Position, Velocity, CompA, CompB, CompC)
    pos = get_component(world, :Position)
    vel = get_component(world, :Velocity)
    A = get_component(world, :CompA)
    B = get_component(world, :CompB)
    C = get_component(world,:CompC)
    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2), Velocity=Velocity(0, 0), CompA=CompA(0, 0), CompB=CompB(0, 0),
         CompC=CompC(0, 0))))
    end

    ids = get_id.(entities)

    return get_iterator((getdata(pos), getdata(vel), getdata(A), getdata(B), getdata(C)), ids)
end

function benchmark_world_set_5(args, n)
    iter = args
    sum = 0.0
    @inbounds for (pos, vel, A, B, C, ids) in iter
        for i in ids
            pos[i] = Position(1, 2)
            vel[i] = Velocity(0, 0)
            A[i] = CompA(0, 0)
            B[i] = CompB(0,0)
            C[i] = CompC(0,0)
        end
    end
end

for n in (100, 10_000)
    SUITE["benchmark_world_set_5_iter n=$n"] = @be setup_world_set_5($n) benchmark_world_set_5(_, $n) seconds = SECONDS
end
