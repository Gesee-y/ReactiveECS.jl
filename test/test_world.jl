


@testset "World Creation" begin
    world = ECSManager()

    @test world.tables[:main] isa ArchTable
    @test world.bitpos == 0

    register_component!(world, CompA)
    @test world.bitpos == 1
    @test world.components_ids[:CompA] == 0
    @test haskey(world.tables[:main].columns, :CompA)
end