
function setup_query_posvel_op(n_entities::Int)
    world = ECSManager()
    register_component!(world, Position)
    register_component!(world, Velocity)

    pos, vel = get_component(world, :Position), get_component(world, :Velocity)
    request_entity!(world, (;Position= (i -> Position(i, i*2)), Velocity=Velocity(1,1)), n_entities)

    return (pos.x, pos.y, vel.dx, vel.dy, @query(world, Position & Velocity))
end

function benchmark_query_posvel_op(args, n)
    x, y, dx, dy, query = args
    @foreachrange query begin
        @inbounds for i in range
            x[i] += dx[i]
            y[i] += dy[i]
        end
    end
end

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_posvel_optimized n=$n"] = @be setup_query_posvel_op($n) benchmark_query_posvel_op(_, $n) seconds = SECONDS
end
