using RECS

@component Health begin
	hp::Int
end

@component Transform begin
    x::Float32
    y::Float32
end

@component Physic begin
    velocity::Float32
end

@system PhysicSystem
@system RenderSystem

function RECS.run!(sys::PhysicSystem, data)
	indices = data.value

	transform_data = get_component(sys, :Transform)
	physic_data = get_component(sys, :Physic)

	x_pos = view(transform_data.x, indices)
	velo = view(physic_data.velocity, indices)

    for i in eachindex(indices)
	    x_pos[i] += velo[i]
    end

    return transform_data
end

function RECS.run!(::RenderSystem, pos)
    for i in eachindex(pos)
		t = pos[i]
	    println("Rendering entity at position ($(t.x), $(t.y))")
	end
end

ecs = ECSManager()

physic_sys = PhysicSystem()
render_sys = RenderSystem()

subscribe!(ecs, physic_sys, (TransformComponent, PhysicComponent))
listen_to(physic_sys,render_sys)

e1 = create_entity!(ecs; Health = HealthComponent(100), Transform = TransformComponent(1.0,2.0))
e2 = create_entity!(ecs; Health = HealthComponent(50), Transform = TransformComponent(-5.0,0.0), Physic = PhysicComponent(1.0))
e3 = create_entity!(ecs; Health = HealthComponent(50), Transform = TransformComponent(-5.0,0.0), Physic = PhysicComponent(1.0))

run_system!(physic_sys)
run_system!(render_sys)

N = 5
target = 16 * 10^6

println("STARTING")
for i in 1:N
    begin
        st = time_ns()
	println("FRAME $i")
	dispatch_data(ecs)
	blocker(ecs)
	dt = (time_ns() - st)

	dt < target && RECS.sleep_ns(target - dt)
    end
end

sleep(2)
