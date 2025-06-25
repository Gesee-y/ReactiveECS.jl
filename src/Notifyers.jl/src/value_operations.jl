############################## Operations for the value state ################################

export does_ignore_eqvalue
export ignore_eqvalue, dont_ignore_eqvalue
export folds

does_ignore_eqvalue(n::Notifyer) = begin
	if is_value_state(n)
		return get_state(n).mode.ignore_eqvalue
	end

	return false
end

function ignore_eqvalue(n::Notifyer)
	if is_value_state(n)
		get_state(n).mode.ignore_eqvalue = true
		return
	end

	throw(StateMismatch("The Notifyer is not in value state. use `enable_value(n::Notifyer)` to set it to the value state."))
end

function dont_ignore_eqvalue(n::Notifyer)
	if is_value_state(n)
		get_state(n).mode.ignore_eqvalue = false
		return
	end

	throw(StateMismatch("The Notifyer is not in value state. use `enable_value(n::Notifyer)` to set it to the value state."))
end

function Base.map(f::Function,n::Notifyer;name=" ", typ=(Any,))

	N = Notifyer(name,typ; parent = WeakRef[WeakRef(n)])
	enable_value(N)

	connect(n) do val...
		N[] = f(val...)
	end

	return N
end

function Base.map(f::Function,ns::Notifyer...;name=" ", typ=(Any,))

	refs = Vector{WeakRef}(undef,length(ns))

	for i in eachindex(ns)
		refs[i] = WeakRef(ns[i])
	end

	N = Notifyer(name,typ; parent = refs)
	enable_value(N)

	for n in ns
		connect(n) do val...
			vals = []
			for par in N.parent
				v = par.value
				v == nothing && return
				push!(vals,par.value[])
			end
			N[] = f((vals...)...)
		end
	end

	return N
end

function folds(f::Function,n::Notifyer;name=" ", typ=(Any,))
	N = Notifyer(name,typ; parent = WeakRef[WeakRef(n)])

	enable_value(N)

	connect(n) do val...
		N[] = f(N[]...,val...)
	end

	return N
end

function Base.filter(f::Function,n::Notifyer;name=" ", typ=(Any,))
	N = Notifyer(name,typ; parent = WeakRef[WeakRef(n)])

	enable_value(N)

	connect(n) do val... 
		if f(val...)
			N[] = val
		end
	end

	return N 
end