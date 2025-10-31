
function setup_query_posvel(n_entities::Int)
    world = ECSManager()
    register_component!(world, Position)
    register_component!(world, Velocity)

    pos, vel = get_component(world, :Position), get_component(world, :Velocity)
    frequest_entity!(world, (;Position= (i -> Position(i, i*2)), Velocity=Velocity(1,1)), n_entities)

    return (pos, vel, @query(world, Position & Velocity))
end

function benchmark_query_posvel(args, n)
    pos_column, vel_column, query = args
    posc = getdata(pos_column)
    velc = getdata(vel_column)
    @foreachrange query begin
        positions = get_block(posc, range[begin])
        velocities = get_block(velc, range[begin])
        r = offset(range, get_offset(posc, range[begin]))
        @inbounds for i in r
            pos = positions[i]
            vel = velocities[i]
            positions[i] = Position(pos.x + vel.dx, pos.y + vel.dy)
        end
    end
end

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    SUITE["benchmark_query_posvel n=$n"] = @be setup_query_posvel($n) benchmark_query_posvel(_, $n) seconds = SECONDS
end
