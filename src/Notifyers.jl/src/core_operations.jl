## The main operations of the Notifyer



"""
	connect(f,notif::AbstractNotifyer;consume=false)

Let the function `f` observe the notifcation `notif`, so that he his updated on change.
if `consume` is true, then the function will be disconnected after being called one time.

```julia-repl

julia> @Notifyer NewMember(name::String)

julia> member_count :: Int64 = 0
0

julia> function _on_new_member(name::String)
			text = ["You are our first member.","You are our second member.","Yay, a third member !",
					"We start to seem like a group.","Now we are like the five finger of the hand",
					"Now we are like the six finger of an alien hand.",
					"If we continue growing like that, we will be able to start our own basketball club.",
					"Feeling happy to have so much friends.","Our group is growing."]

			member_count <= length(text) && println(text[member_count+1])
			println("Welcome \$name !") # remove the '\' when you will be testing this.
	   end

julia> increase_member(_) = global member_count += 1 # _ is just a placeholder.

julia> connect(increase_member,NewMember)

julia> connect(_on_new_member,NewMember)

julia> names = ("Johny","catbot147","pedroGT","PerloMaco","gengenishere83","lowe346","itsnotajoke-sama")

julia> for i in 1:7
			NewMember.emit = names[i]
			sleep(rand() * (7-i)) ## Simulating a hold up before a new member
	   end

## You have the pleasure to test this.
```
"""
function connect(f::Function,notif::Notifyer;consume=false)
	listener = Listener(f,consume)
	push!(listeners(notif),listener)
	precompile(f,eltype(notif))

	return listener
end

"""
	disconnect(f,notif::AbstractNotifyer)

Let you remove a listener `f` of the Notifyer `notif`. `f` can be a `Function` or a `Listener`.
"""
disconnect(f,notif::AbstractNotifyer) = begin
	
	list = listeners(notif)
	for i in eachindex(list)
		if f == list[i]
			deleteat!(list,i)
			break
		end
	end
end

"""
	close(notif::AbstractNotifyer)

end a notification and make it unable to update his listeners.
"""
Base.close(notif::AbstractNotifyer) = (notif.closed[] = true)

"""
	isopen(notif::AbstractNotifyer)

Return true if the Notifyer `notif` is open and can emit, else it return false.
"""
Base.isopen(notif::AbstractNotifyer) = !notif.closed[]

"""
	reset(notif::AbstractNotifyer)

Reset the Notifyer `notif` (remove all listeners, reopen the Notifyer).
Every process that was waiting for `notif` to emit will continue.
"""
Base.reset(notif::AbstractNotifyer) = begin
	notif.closed[] = false
	listener = listeners(notif)
	
	for l in listener
		delete!(listener,l)
	end

	notify(notif.condition)
end

## We modify setproperty! and getproperty for the notifyer.
# So we can easily emit the notifyer.
function Base.setproperty!(notif::AbstractNotifyer,sym::Symbol,v)
	if sym === :emit
		!notif.closed[] && emit(notif,v)
	else
		setfield!(notif,sym,v)
	end
end
function Base.setproperty!(notif::AbstractNotifyer,sym::Symbol,v::Tuple)
	if sym === :emit
		!notif.closed[] && emit(notif,v...)
	else
		setfield!(notif,sym,v)
	end
end
function Base.getproperty(notif::AbstractNotifyer,sym::Symbol)
	if sym === :emit
		!notif.closed[] && emit(notif)
	else
		getfield(notif,sym)
	end
end

function Base.getindex(notif::Notifyer)
	if is_value_state(notif)
		return get_state(notif).mode.value
	end

	throw(StateMismatch("The notifyer is not in value state, use `enable_value(n::Notifyer)` to set it to value state."))
end

function Base.setindex!(notif::Notifyer,value::Tuple)
	if is_value_state(notif)

		emit(notif,value...)
		return
	end

	throw(StateMismatch("The notifyer is not in value state, use `enable_value(n::Notifyer)` to set it to value state."))
end

function Base.setindex!(notif::Notifyer,value)
	if is_value_state(notif)

		emit(notif,value)
		return
	end

	throw(StateMismatch("The notifyer is not in value state, use `enable_value(n::Notifyer)` to set it to value state."))
end

"""
	emit(notif::AbstractNotifier,args...)

Emit the Notifyer `notif` with the argument `args` which will update all his listeners.
An alternative to this function is `notifyer_name.emit = args`.
If there is no argument, just use `notifyer_name.emit` to update the listeners.
"""
function emit(notif::Notifyer,@nospecialize(args...))
	if !isempty(notif.listeners)
		state = get_state(notif)

		if check_value(notif)
			notifArgs = getargs(notif)
			if (length(args) < length(notifArgs))

				for i in eachindex(notifArgs)
					if isa(notifArgs[i],Pair) || typeof(notifArgs[i]) != DataType
						args = tuple(args...,getvalues(notif)[i:end]...)
						break
					end
				end
			end

			if !_signature_matching(notifArgs,args)
				throw(ArgumentError("Signature does not match. Notifyer accept $(eltype(notif)) but receive $args of type $(typeof.(args))"))
			end
		end

		notifyer_process(state.mode, notif, args)
		notify(notif.condition)
		put!(get_stream(state),EmissionCallback{Listener}(listeners(notif)))

		emission_process(state.emission, state.exec, notif, args)
	else
		notify(notif.condition)
	end
end

"""
	wait(notif::AbstractNotifyer)

Stop the current process and wait for the Notifyer `notif` to emit before continuing.
"""
Base.wait(notif::AbstractNotifyer) = wait(notif.condition)

"""
	listeners(notif::AbstractNotifyer)

Return a the listeners of the Notifyer `notif`.
"""
listeners(notif::AbstractNotifyer) = getfield(notif,:listeners)
