
include("..\\src\\ReactiveECS.jl")

using .ReactiveECS
using BenchmarkTools
using Chairmarks

const SECONDS = 0.5
const SUITE = BenchmarkGroup()

include("BenchTypes.jl")

include("bench_query_create.jl")
include("bench_query_posvel.jl")
# include("bench_query_posvel_optim.jl")
include("bench_world_posvel.jl")
include("bench_world_get_1.jl")
include("bench_world_get_5.jl")
include("bench_world_set_1.jl")
include("bench_world_set_1_iter.jl")
include("bench_world_set_5.jl")
include("bench_world_set_5_iter.jl")
include("bench_world_new_entity_1.jl")
include("bench_world_new_entity_5.jl")
include("bench_world_add_remove.jl")
include("bench_world_add_remove_large (2).jl")
#include("bench_world_add_remove_8.jl")
#include("bench_world_add_remove_8_large.jl")
