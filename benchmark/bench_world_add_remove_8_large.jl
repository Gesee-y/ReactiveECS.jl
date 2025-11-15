
function setup_world_add_remove_8_large(n_entities::Int)
    world = ECSManager(Position,
        Comp1, Comp2, Comp3, Comp4, Comp5,
        Comp6, Comp7, Comp8, Comp9, Comp10,
        Comp11, Comp12, Comp13, Comp14, Comp15,
        Comp16, Comp17, Comp18, Comp19, Comp20,
        Comp21, Comp22, Comp23, Comp24, Comp25,
        Comp26, Comp27, Comp28, Comp29, Comp30,
        Comp31, Comp32, Comp33, Comp34, Comp35,
        Comp36, Comp37, Comp38, Comp39, Comp30,
        Comp41, Comp42, Comp43, Comp44, Comp45,
        Comp46, Comp47, Comp48, Comp49, Comp50,
        Comp51, Comp52, Comp53, Comp54, Comp55,
        Comp56, Comp57, Comp58, Comp59, Comp60,
        Comp61, Comp62,
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

function benchmark_world_add_remove_8_large(args, n)
    entities, world = args
    attach_component(world, entities, Comp1(0, 0), Comp2(0, 0), Comp3(0, 0), Comp4(0, 0),
            Comp5(0, 0), Comp6(0, 0), Comp7(0, 0), Comp8(0, 0))
    detach_component(world, entities, :Comp1, :Comp2, :Comp3, :Comp4, :Comp5,
            :Comp6, :Comp7, :Comp8)
end

for n in (100, 10_000, 100000)
    SUITE["benchmark_world_add_remove_8_large n=$n"] = @be setup_world_add_remove_8_large($n) benchmark_world_add_remove_8_large(_, $n) seconds = SECONDS
end
