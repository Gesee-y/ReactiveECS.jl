############################################################ OVERHEAD TEST ##############################################

include(joinpath("..","src","ReactiveECS.jl"))
using .ReactiveECS
using BenchmarkTools
using LoopVectorization

const MILLION = 1_000_000
const BILLION = MILLION*1000
const ENTITY_COUNT = 255000
const COMPONENT_COUNT = 10
const QUERY_COUNT = 3
const SAMPLE_COUNT = 100

TList = []

for i in 1:COMPONENT_COUNT
	T = Symbol("T$i")
	eval(
	quote
		@component $T begin
		    x::Int
		end
	end)
end
@generated function create_components(ecs::ECSManager)
	ex = Expr(:block)
	for i in 1:COMPONENT_COUNT
	    T = Symbol("T$i")
		push!(ex.args, :(register_component!(ecs, $T)))
	end
    
    return ex
end
flip_coin() = rand() > 0.5

world = ECSManager()
create_components(world)

for i in 1:ENTITY_COUNT
    ent = create_entity!(world, ())

    for c in 1:COMPONENT_COUNT
    	T = Symbol("T$c")
    	flip_coin() && attach_component(world, ent, eval(:($T($i))))
    end
end

println("entities created: $ENTITY_COUNT ($COMPONENT_COUNT randomized components)")
println("partitions created: $(length(world.tables[:main].partitions))")
println("")

cols = world.tables[:main].columns
println(Base.summarysize(collect(values(cols)))/1024, "Ko")