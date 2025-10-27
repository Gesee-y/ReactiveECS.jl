
function setup_world_add_remove_large_world(n_entities::Int)
    world = ECSManager(
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
        Position, Velocity,
    )

    entities = Vector{Entity}()
    for i in 1:n_entities
        push!(entities, create_entity!(world, (; Position=Position(i, i*2))))
    end

    for e in entities
        attach_component(world, e, Velocity(0,0))
        detach_component(world, e, :Velocity)
    end

    return (entities, world)
end

function benchmark_world_add_remove_large_world(args, n)
    ents, world = args
    attach_component(world, ents, Velocity(0,0))
    detach_component(world, ents, :Velocity)
end

for n in (100, 10_000)
    SUITE["benchmark_world_add_remove_large n=$n"] = @be setup_world_add_remove_large_world($n) benchmark_world_add_remove_large_world(_, $n) seconds = SECONDS
end
