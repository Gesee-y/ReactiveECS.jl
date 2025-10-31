
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

    ids = getindex.(get_id.(entities))

    return get_iterator(getdata(pos), ids), get_iterator(getdata(vel), ids), get_iterator(getdata(A), ids), get_iterator(getdata(B), ids), get_iterator(getdata(C), ids)
end

function benchmark_world_set_5(args, n)
    pos_iter, vel_iter, A_iter, B_iter, C_iter = args
    sum = 0.0
    for j in eachindex(pos_iter)
        ids = pos_iter[j][2]
        pos = pos_iter[j][1]
        vel = vel_iter[j][1]
        A = A_iter[j][1]
        B = B_iter[j][1]
        C = C_iter[j][1]

        @inbounds for i in ids
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
