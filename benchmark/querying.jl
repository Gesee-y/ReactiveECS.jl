#########################################################################################################################
####################################################### MANAGER #########################################################
#########################################################################################################################

include("..\\src\\ReactiveECS.jl")
using .ReactiveECS
using BenchmarkTools
using LoopVectorization

@component Position begin
    x::Float64
    y::Float64
end
@component Velocity begin
    dx::Float64
    dy::Float64
end

function setup_world(n_entities::Int)
    world = ECSManager()
    register_component!(world, Position)
    register_component!(world, Velocity)

    pos, vel = get_component(world, :Position), get_component(world, :Velocity)
    request_entity!(world, (;Position= (i -> Position(i, i*2)), Velocity=Velocity(1,1)), n_entities)

    return (pos.x, pos.y, vel.dx, vel.dy, @query(world, Position & Velocity))
end

function benchmark_iteration(n)
    bench = @benchmarkable begin
        x, y, dx, dy, query = data
        @foreachrange query begin
            @turbo for i in range
                x[i] += dx[i]
                y[i] += dy[i]
            end
        end
    end setup = (data = setup_world($n))

    println("\nBenchmarking with $n entities...")
    tune!(bench)
    result = run(bench, seconds=10)
    println("Mean time per entity: $(time(mean(result)) / n) ns")
    display(result)
end

for n in (100, 1_000, 10_000, 100_000)
    benchmark_iteration(n)
end
