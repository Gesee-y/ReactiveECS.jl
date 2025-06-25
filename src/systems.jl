##################################################################################################################
###################################################   SYSTEM   ###################################################
##################################################################################################################

export @system
export subscribe!, unsubscribe!, listen_to, get_into_flow
export run!, run_system!, get_profile_stats

const SYS_CHANNEL_SIZE = 64
"""
    @system sys_name

This macro serve to create a new system . You can initialize it with just `sys_name()`.

    @macro sys_name begin
        field1
        field2
          .
          .
          .
        fieldn
    end

This macro can be used to create a new system with additional fields
"""
macro system(name)
	logname = Symbol(string(name)*"Log")
	eval(:(@logdata $logname))
	return quote
		mutable struct $name <: AbstractSystem
			active::Bool
			flow::Channel
			archetype::BitType
			position::Int
			ecs::WeakRef
			children::Vector{AbstractSystem}
			logdata::$logname
			
			## Constructors

			$name() = new(true,Channel(SYS_CHANNEL_SIZE), init(BitType), 0, WeakRef(nothing), AbstractSystem[], $logname())
		end
	end
end
macro system(name, block)
	logname = Symbol(string(name)*"Log")
	eval(:(@logdata $logname))
	ex = quote
		mutable struct $name <: AbstractSystem
			active::Bool
			flow::Channel
			archetype::BitType
			position::Int
			ecs::WeakRef
			children::Vector{AbstractSystem}
			logdata::$logname
			
			## Constructors

			$name(args...) = new(true,Channel(SYS_CHANNEL_SIZE), init(BitType), 0, WeakRef(nothing), AbstractSystem[], $logname(), args...)
		end
	end

	args = ex.args[2].args[3].args
	fun = pop!(args)
	append!(args, block.args)
	push!(args, fun)
	return ex
end

############################################### System Management ################################################

"""
    run!(sys::T, data) where T <: AbstractSystem

This function should be overloaded for every system. It's the task they will execute
If the system have subscribed to the manager, `data` will be a tuple, were the 1st is a weak references to the data
and the 2nd is a weak references to the indices of the entities requested by the system
"""
run!(sys::T, batch) where T <: AbstractSystem = error("run! is not defined for the system of type $T")

function run_system!(@nospecialize(system::AbstractSystem))
    
    ecs = system.ecs.value
    system.active = true
    isnothing(ecs) && error("System $system can't run without being recognized in the ECS. 
    	Add him with subscribe!, listen_to or get_into_flow.")
    atomic_add!(ecs.sys_count,1)

    # The system will run as an asynchronous task
    # We can stop it at anytime with system.active
	@spawn while system.active
		batch = take!(system.flow)

		try

			# First we check if this is the last system running
			ecs.sys_done[] >= ecs.sys_count[] && atomic_sub!(ecs.sys_done,1)
		    debug = debug_mode()
		    result = nothing

		    # If we are in debug mode
		    # We will log the data received, the run statistics and the value returned
		    if debug
		    	Log!(ecs.logger, system.logdata, INFO, "Received data : $batch")
		    	system.logdata.stats = @timed run!(ecs, system, batch)
		    	result = system.logdata.stats.value
		        Log!(ecs.logger, system.logdata, INFO, "Returning data : $result")
		    else
		    	result = run!(ecs, system, batch)
		    end
		    
		    # We then give the result to the listening system
			feed_children(system, result)

			# And atomically add him to the done systems
			atomic_add!(ecs.sys_done,1)
	    catch e
	    	# We stop the system and we remove it from the running ones
	    	atomic_sub!(ecs.sys_count,1)

	    	# We log since it's a critical problem
	    	Log!(ecs.logger, system.logdata, ERROR, "Encountered an $e")
	    	system.active = false # We finally stop the system
		finally
			# We check if the system it's the last system running and if there is no more data to process
			if ecs.sys_done[] >= ecs.sys_count[] && isempty(system.flow)
				put!(ecs.blocker, 1) # We unblock the ecs's blocker
				ecs.sys_done[] = 0 # And we reset the counter
			end
	    end

	    yield()
	end
end

function feed_children(@nospecialize(sys::AbstractSystem), data)
	children::Vector{AbstractSystem} = sys.children
		
	for child in children
		put!(child.flow, data)
	end
	
end

"""
    get_profile_stats(sys::AbstractSystem)

This function will return the statistics of the last run of a system
These statistics are in the same format as those returned by `@timed`
"""
get_profile_stats(sys::AbstractSystem) = sys.logdata.stats

"""
    get_component(sys::AbstractSystem, s::Symbol)

This return the SoA of a component of name `s`.
The system should have subscribed to the manager or be listening to another one for this to work
"""
get_component(sys::AbstractSystem, s::Symbol) = sys.ecs.value != nothing ? get_component(sys.ecs.value, s) : error("The system hasn't subcribed yet to the manager.")

"""
    listen_to(source::AbstractSystem, listener::AbstractSystem)

This function make the system `listener` wait for data coming from the system `source`
"""
@inline Base.@nospecializeinfer function listen_to(@nospecialize(source::AbstractSystem), @nospecialize(listener::AbstractSystem))

	## We will skip error checking on purpose
	# We are just fetching data so there should be not problem
	# We will just async this to ensure that we are still on the main thread
    _check_cycle(source, listener)
    push!(source.children, listener)

    listener.ecs = source.ecs
end

"""
    get_into_flow(source::AbstractSystem, system::AbstractSystem)

Use this function to make a system get into the execution's flow.
the `system` will be connected as a child of `source` and will get all its listeners.
the `source` system will only have `system` as listener
"""
function get_into_flow(source::AbstractSystem, system::AbstractSystem)
	system.children = copy(source.children)
	source.children = AbstractSystem[system]

	listener.ecs = source.ecs
end

"""
    listen_to(ecs::ECSManager, archetype::NTuple{N,Symbol}, listener::AbstractSystem, num=1) where N

This function will make the system `listener` wait for data coming the `num` systems who have request the components `archetype`
"""
function listen_to(ecs::ECSManager, components::Tuple, listener::AbstractSystem, num=1)
	archetype = get_bits(components)
	if haskey(ecs.archetypes, archetype)
		source = get_systems(ecs.archetypes[archetype])

		(num == -1) && (num = length(source))
		for i = 1:num
		    listen_to(source[i], listener)
		end
	else
		@warn "There is no system matching the archetype $archetype yet."
	end
end

"""
    subscribe!(ecs::ECSManager, system::AbstractSystem, components::Tuple)

This function makes the system subscribe to a set of archetype.
`component` is a tupe of type, each type is a component's type
"""
function subscribe!(ecs::ECSManager, system::AbstractSystem, components::Tuple)
	
	# If the is not system with a subscription to the given archetype
	archetype = get_bits(BitType,components)
	
	if !haskey(ecs.archetypes, archetype)

		# Setting some little hooks
		system.archetype = archetype
		system.position = 1
		indices = Int[]

		# Creating the new data for the archetype
		archetype_data = ArchetypeData(indices, Dict{Int, Int}(), AbstractSystem[system])
		ecs.archetypes[archetype] = archetype_data

		# We will now put all the entities matching that archetype in indices
		for entity in ecs.entities
			if _match_archetype(entity, archetype)
				id = get_id(entity)
				push!(indices, id)
				archetype_data.positions[id] = length(indices)-1
			end
		end
	else
		systems = get_systems(ecs.archetypes[archetype])
		push!(systems, system)
		system.position = length(systems)
	end

	system.ecs = WeakRef(ecs)

	return nothing
end

"""
    unsubscribe!(ecs::ECSManager, system::AbstractSystem)

This function will make a system stop waiting for data from a given archetype
"""
function unsubscribe!(ecs::ECSManager, system::AbstractSystem)
	deleteat!(get_systems(ecs.archetypes[system.archetype]), system.position)
end

Base.println(io::IO, sys::AbstractSystem) = _print(println, io, sys)
Base.print(io::IO, sys::AbstractSystem) = _print(print, io, sys)
Base.println(sys::AbstractSystem) = _print(println, stdout, sys)
Base.print(sys::AbstractSystem) = _print(print, stdout, sys)
function _print(f::Function, io::IO, sys::T) where T <: AbstractSystem
	str = ""
	fields = propertynames(sys)
	custom_field_offset = 8
	for i in custom_field_offset:length(fields)
		str *= "\t$(fields[i])=$(getproperty(sys, fields[i]))\n"
	end
	f("$T : \n$str")
end
################################################# Helpers ######################################################

function _check_cycle(source, listener)
	(source == listener) && error("Cycle detected in listen_to($source, $listener)")
	for child in source.children
		_check_cycle(child, listener)
	end
end