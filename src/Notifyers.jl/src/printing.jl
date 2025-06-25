## ------------------------------------- Printing ----------------------------------------- ##
##############################################################################################

function Base.show(io::IO,n::AbstractNotifyer)
	T = typeof(n)
	list = listeners(n)
	len = length(list)
	can_emit = isopen(n)

	println(io,"$T with $len listeners. Open = $can_emit :")
	for l in list
		println("\t",l)
	end
end

function Base.show(io::IO,l::Listener)
	print("Listener function `$(l.f)`.")
end
Base.show(l::Listener) = show(stdout,l)

Base.print(io::IO,l::Listener) = show(io,l)
Base.print(l::Listener) = Base.print(stdout,l)

Base.println(io::IO,l::Listener) = (print(io,l);print(io,"\n"))
Base.println(l::Listener) = println(stdout,l)

Base.print(io::IO,n::AbstractNotifyer) = show(io,n)
Base.print(n::AbstractNotifyer) = print(stdout,n)
Base.println(io::IO,n::AbstractNotifyer) = (show(io,n);print(io,"\n"))
Base.println(n::AbstractNotifyer) = println(stdout,n)
