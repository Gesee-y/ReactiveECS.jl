
function setup_world_get_5(n_entities::Int)
    world = ECSManager(Position, Velocity, CompA, CompB, CompC)

    pos, vel, A, B, C = (get_component(world, :Position), get_component(world, :Velocity), get_component(world, :CompA), 
        get_component(world, :CompB), get_component(world, :CompC))
    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i * 2), Velocity=Velocity(0, 0), CompA=CompA(0, 0), 
            CompB=CompB(0, 0), CompC=CompC(0, 0))))
    end

    ids = getindex.(get_id.(entities))

    return get_iterator(getdata(pos), ids), get_iterator(getdata(vel), ids), get_iterator(getdata(A), ids), get_iterator(getdata(B), ids), get_iterator(getdata(C), ids)
end

function benchmark_world_get_5(args, n)
    pos_iter, vel_iter, A_iter, B_iter, C_iter = args
    sum = 0.0
    @inbounds for j in eachindex(pos_iter)
        ids = pos_iter[j][2]
        position = pos_iter[j][1]
        velocity = vel_iter[j][1]
        A = A_iter[j][1]
        B = B_iter[j][1]
        C = C_iter[j][1]
        @inbounds for i in ids
            pos, vel, a, b, c = position[i], velocity[i], A[i], B[i], C[i]
            sum += pos.x + vel.dx + a.x + b.x + c.x
        end
    end
    return sum
end

for n in (100, 1_000, 10_000, 100_000)
    SUITE["benchmark_world_get_5 n=$n"] = @be setup_world_get_5($n) benchmark_world_get_5(_, $n) seconds = SECONDS
end
