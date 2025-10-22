using BenchmarkTools


let world = ECSManager()
	table = world.tables[:main]
	register_component!(world, CompA)
	register_component!(world, CompB)

	@testset "Table initialization" begin
		a1 = 0x1
		RECS.createpartition(table, a1)

		@test haskey(table.partitions, a1)
		pt1 = table.partitions[a1]

		@test !isempty(pt1.zones) && !isempty(pt1.to_fill)
		@test RECS.get_range(pt1.zones[1]) == 1:0
		@test pt1.to_fill[1] == 1
	end

	@testset "Making rows" begin
	    a1 = 0x1
	    t = 0.0
	    int1 = RECS.allocate_entity(table, 100, a1)

		@test !isempty(int1)
		@test int1[1] == 1:100

		pt1 = table.partitions[a1]
		@test get_range(pt1.zones[1]) == int1[1]
		@test pt1.to_fill[1] == 1
		
		int2 = RECS.allocate_entity(table, 4100-100, a1)
		@test get_range(pt1.zones[1]) == 1:4096
		@test pt1.to_fill[1] == 2
		@test get_range(pt1.zones[2]) == 4096:4100
	end
end