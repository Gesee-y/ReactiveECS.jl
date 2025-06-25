## Printing a NodeTree ##

export TreeCharSet, print_tree, get_charset

struct TreeCharSet
	branch :: String
	terminator :: String
	midpoint :: String
	indent :: String
	link :: String
end
Base.getindex(t::TreeCharSet,i) = getfield(t,:charset)[i]

const DefaultCharset = TreeCharSet("├","└","│","\t","─")
get_charset() = DefaultCharset

function print_tree(io::IO,n::AbstractNode;decal=0,mid=1,charset=get_charset())
	childrens = get_children(n)

	print("Node ",n.name, " : ")
	print(nvalue(n))

	for i in eachindex(childrens)
		println()
		child = childrens[i]

		for i in 1:decal+1
			i > mid && print(charset.midpoint)
			print(charset.indent)
		end

		if i < length(childrens) && !(decal-1>0)
			print(charset.branch)
		elseif !(decal-1>0)
			print(charset.terminator)
		end
		print(io,charset.link)

		print_tree(io,child;decal=decal+1,mid=(decal+1) + Int(i==length(childrens)))
	end
end	
function print_tree(io::IO,n;decal=0,mid=1,charset=get_charset())
	childrens = get_children(n)

	print(typeof(n)," : ")
	print(nvalue(n))

	for i in eachindex(childrens)
		println()
		child = childrens[i]

		for i in 1:decal+1
			i > mid && print(charset.midpoint)
			print(charset.indent)
		end

		if i < length(childrens) && !(decal-1>0)
			print(charset.branch)
		elseif !(decal-1>0)
			print(charset.terminator)
		end
		print(io,charset.link)

		print_tree(io,child;decal=decal+1,mid=(decal+1) + Int(i==length(childrens)))
	end
end
function print_tree(io::IO,t::ObjectTree)
	childs = get_children(get_root(t))
	print(io,"Object Tree with $(get_object_count(t)) Node :")
	println()

	for child in childs
		print_tree(io,child)
		println(io)
	end
end
print_tree(obj) = print_tree(stdout,obj)

Base.show(io::IO,n::AbstractNode) = print_tree(io,n)
Base.show(n::AbstractNode) = show(stdout,n)

Base.print(io::IO,n::AbstractNode) = show(io,n)
Base.print(n::AbstractNode) = show(n)

Base.println(io::IO,n::AbstractNode) = (show(is,n);print("\n"))
Base.println(n::AbstractNode) = (show(n);print("\n"))
