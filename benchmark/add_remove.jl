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
    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2))))
    end

    for e in entities
        attach_component(world, e, Velocity(0,0))
        detach_component(world, e, :Velocity)
    end

    return (world, entities)
end

function benchmark_iteration(n)
    bench = @benchmarkable begin
        ents::Vector{Entity} = entities
        for e in ents
            attach_component(world, e, Velocity(0,0))
            detach_component(world, e, :Velocity)
        end
    end setup = ((world, entities) = setup_world($n))

    println("\nBenchmarking with $n entities...")
    tune!(bench)
    result = run(bench, seconds=10)
    println("Mean time per entity: $(time(mean(result)) / n) ns")
    display(result)
end

for n in (100, 1_000, 10_000, 100_000)
    benchmark_iteration(n)
end
