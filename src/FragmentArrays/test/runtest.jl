include(joinpath("..", "src", "FragmentArrays.jl"))

using .FragmentArrays
using BenchmarkTools

a = FragmentVector{Int}(undef, 10)

a[5] = 1
a[3] = 2
println(a.data)
println(a.offset)
println(a.map)
println(a[3])
a[4] = 3
println(a.data)
println(a.offset)
println(a.map)

b = [1,2,3]

@btime @inbounds $b[3]
@btime @inbounds $a[3]

@time a[6] = 5
println(a.data)
println(a.offset)
println(a.map)

deleteat!(a, 6)
println(a.data)
println(a.offset)
println(a.map)

@time deleteat!(a, 4)
println(a.data)
println(a.offset)
println(a.map)
