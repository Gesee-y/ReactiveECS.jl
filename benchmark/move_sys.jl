include("..\\src\\ReactiveECS.jl")
using .ReactiveECS
using BenchmarkTools
using LoopVectorization

@component Position begin
    x::Float64
    y::Float64
    z::Float64
end
@component Velocity begin
    dx::Float64
    dy::Float64
    dz::Float64
end

function setup_world(n_entities::Int)
    world = ECSManager()
    register_component!(world, Position)
    register_component!(world, Velocity)

    pos, vel = get_component(world, :Position), get_component(world, :Velocity)
    request_entity!(world, (;Position= (i -> Position(i, i*2, i*3)), Velocity=Velocity(1,1,1)), n_entities)

    return (pos.x, pos.y, pos.z, vel.dx, vel.dy, vel.dz, @query(world, Position & Velocity))
end

function benchmark_iteration(n)
    bench = @benchmarkable begin
        x, y, z, dx, dy, dz, query = data
        @foreachrange query begin
            @inbounds for i in range
                x[i] += dx[i]
                y[i] += dy[i]
                z[i] += dz[i]
            end
        end
    end setup = (data = setup_world($n))

    println("\nBenchmarking with $n entities...")
    tune!(bench)
    result = run(bench, seconds=10)
    println("Mean time per entity: $(time(mean(result)) / n) ns")
    display(result)
end

for n in (15_000_000)
    benchmark_iteration(n)
end
