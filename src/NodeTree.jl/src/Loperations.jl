## Operations for linked Nodes ##

is_orphan(n::AbstractNode) = !(get_tree(n).value isa AbstractTree)

get_tree(n::LNode) = getfield(n,:tree)

get_childrens(n::LNode) = getfield(n,:childrens)
get_childrens(r::LinkedRoot) = getfield(r,:childs)

"""
	get_nodeidx(n::LNode,relative::Bool=false)

Return the index of a Node n relatively to the Root of the tree(if it's in it), or to his parent
if relative is true.
"""
get_nodeidx(n::LNode,relative::Bool=false) = relative ? getfield(n,:idx)[end] : getfield(n,:idx)

"""
	set_nodeidx(n::LNode,idx::Tuple)

Set the index of the Node `n` with `idx`.
"""
set_nodeidx(n::LNode,idx::Tuple) = setfield!(n,:idx,idx)

function get_node(n::LNode,idx::Tuple)
	current_node = n
	for i in idx
		current_node = get_child(current_node,i)
	end

	return current_node
end
get_node(n::LNode,idx...) = get_node(n,idx)
get_node(root::LinkedRoot,idx::Tuple) = get_node(get_objects(root)[idx[1]],idx[2:end])
get_node(root::LinkedRoot,idx...) = get_node(root,idx)

"""
	get_parent(n::LNode)

Return the parent of a given node
"""
get_parent(n::LNode) = begin 
	idx = get_nodeidx(n)
	tree = get_tree(n).value
	if length(idx) < 2
		return get_root(tree)
	else
		return get_node(get_root(tree),idx[begin:end-1])
	end
end

"""
	nvalue(n::LNode)

Return the value contained by a LinkedNode `n`.
"""
nvalue(n::LNode) = getfield(n,:self)

"""
	get_siblings(n::LNode)

Return all the Nodes with the same parent as `n`.
"""
function get_siblings(n::LNode)
	parent = get_parent(n)
	children = get_childrens(parent)
	i = get_nodeidx(n,true)

	return [children[begin:i-1];children[i+1:end]]
end

remove_child(n::LNode,i::Int) = deleteat!(get_childrens(n),i)
remove_node(tree::LinkedTree,n::LNode) = remove_child(get_parent(n),get_nodeidx(n,true))

"""
	add_child(n::LNode,obj)

Use this to add a child to a LNode.
"""
function add_child(n::LNode,n2::LNode)
	
	childrens = get_childrens(n)
	i = length(childrens)+1
	id = tuple(get_nodeidx(n)...,i)

	n2.tree = n.tree
	set_nodeidx(n2,id)

	push!(childrens,n2)
end
function add_child(tree::LinkedTree,N::LNode)
	objects = get_allnode(get_root(tree))

	N.tree = WeakRef(tree)
	Nchildrens = get_childrens(N)
	push!(objects,N)

	set_nodeidx(N,(length(objects),))
end
add_child(n::LNode,obj;name=_generate_node_name()) = add_child(n,LNode(obj,name))
add_child(t::LinkedTree,obj;name=_generate_node_name()) = add_child(t,LNode(obj,name))