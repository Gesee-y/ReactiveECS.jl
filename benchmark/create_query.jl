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

function setup_world(n)
    world = ECSManager(Position, Velocity)
    queries = Vector{Query}(undef, n)

    return world, queries
end

function benchmark_query_create(n)
    bench = @benchmarkable begin
        for i in 1:$n
            queries[i] = @query(world, Position & Velocity)
        end
    end setup = (world,queries) = setup_world($n)

    println("\nBenchmarking with $n queries...")
    tune!(bench)
    result = run(bench, seconds=10)
    println("Mean time per query: $(time(mean(result)) / n) ns")
    display(result)
end

for n in (100, 1_000, 10_000, 100_000, 1_000_000)
    benchmark_query_create(n)
end
