
include("..\\src\\ReactiveECS.jl")
using .ReactiveECS
using Test

const RECS = ReactiveECS

@component CompA begin
	a::Int
end
@component CompB begin
	b::Int
end

include("test_world.jl")
include("test_table.jl")