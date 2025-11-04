
function setup_world_add_remove_8(n_entities::Int)
    world = ECSManager(Position,
        Comp1, Comp2, Comp3, Comp4, Comp5,
        Comp6, Comp7, Comp8,
    )

    entities = Entity[]

    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2))))
    end

    for e in entities
        attach_component(world, e, Comp1(0, 0), Comp2(0, 0), Comp3(0, 0), Comp4(0, 0),
            Comp5(0, 0), Comp6(0, 0), Comp7(0, 0), Comp8(0, 0))
        detach_component(world, e, :Comp1, :Comp2, :Comp3, :Comp4, :Comp5,
            :Comp6, :Comp7, :Comp8)
    end

    return (entities, world)
end

function benchmark_world_add_remove_8(args, n)
    entities, world = args
    attach_component(world, entities, Comp1(0, 0), Comp2(0, 0), Comp3(0, 0), Comp4(0, 0),
            Comp5(0, 0), Comp6(0, 0), Comp7(0, 0), Comp8(0, 0))
    detach_component(world, entities, :Comp1, :Comp2, :Comp3, :Comp4, :Comp5,
            :Comp6, :Comp7, :Comp8)
end

for n in (100, 10_000, 100_000)
    SUITE["benchmark_world_add_remove_8 n=$n"] = @be setup_world_add_remove_8($n) benchmark_world_add_remove_8(_, $n) seconds = SECONDS
end
