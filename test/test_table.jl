using BenchmarkTools

## DEFAULT_PARTITION_SIZE = 4096

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
		@test pt1.fill_pos[1] == 1
	end
	

	@testset "Allocating rows" begin
	    a1 = 0x1
	    int1 = RECS.allocate_entity(table, 100, a1)

		@test !isempty(int1)
		@test int1[1] == 1:100

		pt1 = table.partitions[a1]
		@test get_range(pt1.zones[1]) == int1[1]
		@test pt1.fill_pos == 1
		
		# Now we will trying filling a partition
		int2 = RECS.allocate_entity(table, 4100-100, a1)
		@test get_range(pt1.zones[1]) == 1:4096
		@test pt1.fill_pos == 2
		@test get_range(pt1.zones[2]) == 4098:4101

		# Since we filled a partitions a new one should have been created
		@test length(table.entities) == length(table.columns[:CompA]) == table.row_count == 8194
	end

	@testset "Adding rows" begin
		a1 = 0x1
		a2 = 0x2

		pt1 = table.partitions[a1]
		RECS.addtopartition(table, a1)

		@test get_range(pt1.zones[2]) == 4098:4102

		RECS.createpartition(table, a2)
		RECS.addtopartition(table, a2)

		pt2 = table.partitions[a2]
		@test get_range(pt2.zones[1]) == 8195:8195
		@test !isempty(pt2.to_fill)
		@test length(table.entities) == length(table.columns[:CompB]) + 1  == table.row_count == 12291

		RECS.allocate_entity(table, 4095, a2)

		@test length(table.entities) == length(table.columns[:CompB]) + 1  == table.row_count == 12291
		RECS.addtopartition(table, a2)
		@test length(table.entities) == length(table.columns[:CompB]) + 1 == table.row_count == 16389
		@test get_range(pt2.zones[2]) == 12292:12292
	end

	@testset "Table Mutations" begin
	    id1, id2, id3 = (1 << 32) | 1, (1 << 32) | 4096, (2 << 32) | 12292
		e1, e2, e3 = RECS.getrow(table, id1), RECS.getrow(table, id2), RECS.getrow(table, id3)
		temp_e1 = copy(e1)

		RECS.swap!(table, id1, id2; fields=(:CompA,))
		@test RECS.getrow(table, id1) == e2
	end
end