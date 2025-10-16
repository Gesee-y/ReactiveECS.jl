############################################################ OVERHEAD TEST ##############################################

include(joinpath("..","src","ReactiveECS.jl"))
using .ReactiveECS
using BenchmarkTools

const MILLION = 1_000_000
const BILLION = MILLION*1000
const ENTITY_COUNT = 255
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
    	flip_coin() && attach_component(world, ent, eval(:($T(0))))
    end
end

println("entities created: $ENTITY_COUNT ($COMPONENT_COUNT randomized components)")
println("partitions created: $(length(world.tables[:main].partitions))")
println("")
println("Quering for $QUERY_COUNT components")

q1 = @query(world, T1)
q2 = @query(world, T2)
q3 = @query(world, T3)

function measure_query(query)
	@benchmark begin
	    entity_sum = 0
	    entity_count = 0
		@foreachrange $query begin
		    for i in range
		    	entity_sum += i
		        entity_count += 1
		    end
		end
	end
end

res = measure_query(q1)
res2 = measure_query(q2)
res3 = measure_query(q3)
println(res)
println(res2)
println(res3)