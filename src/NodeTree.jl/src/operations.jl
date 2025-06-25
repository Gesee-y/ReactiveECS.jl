## Operation on NodeTree ##

export get_allnode, is_leave, is_orphan, get_node, get_root, get_tree
export get_nodeidx, set_nodeidx, nvalue, get_children, get_parent, BFS_search, DFS_search
export get_leaves, add_child, remove_child, remove_node, merge_tree!

"""
	get_allnode(root)

Return all the objects contained in the root of a tree, not recommended to use this function
but if you want to create your own Tree, you will have to overload this.
"""
get_allnode(root::AbstractRoot) = getfield(root,:childs)

"""
	is_leave(n::Node)

Return true if the Node `n` has no childrens, else false.
"""
is_leave(n) = isempty(get_children(n))
is_leave(n::Node) = isempty(getfield(n,:childrens))

"""
	is_orphan(root::Abstractroot,n::Node)

Return true is the Node `n` is not in the `Root` root. 
"""
is_orphan(tree::AbstractTree,n::Node) = !(get_nodeidx(n) in tree.objects)

"""
	get_children(n::Node)

Return all the childrens of the Node `n`.
"""
get_children(n::AbstractNode;except=()) = begin
	_clean_children(n)

	childrenID = getfield(n,:childrens)
	arr = Vector{Node}(undef,length(childrenID))

	for i in eachindex(childrenID)
		condition = !(childrenID[i] in except)
		if condition
			arr[i] = get_node(n,childrenID[i])
		end
	end

	return arr
end
get_children(r::AbstractRoot) = begin

	childrenID = get_allnode(r) 
	arr = Vector{Node}(undef,length(childrenID))
	tree = get_tree(r).value
	for i in eachindex(childrenID)
		arr[i] = get_object(tree,childrenID[i])
	end

	return arr
end

"""
	get_nodeidx(n::AbstractNode,relative::Bool=false)

Return the index of a Node n relatively to the Root of the tree(if it's in it), or to his parent
if relative is true.
"""
@noinline get_nodeidx(n::AbstractNode,relative::Bool=false) = relative ? getfield(n,:ID)[end] : getfield(n,:ID)

"""
	set_nodeidx(n::AbstractNode,idx::Tuple)

Set the index of the Node `n` with `idx`.
"""
@inline set_nodeidx(n::AbstractNode,idx::Integer) = setfield!(n,:ID,UInt(idx))

@nospecialize
"""
	get_child(n,i)

Get the child of the Node `n` at the index `i`
"""
get_child(n,i::Int) = get_children(n)[i]

"""
	get_node(root,idx)

Get the Node corrsponding to the given index `idx`
"""
get_node(n,idx::Integer) = get_object(get_tree(n).value,idx)
get_node(tree::AbstractTree,idx::Integer) = get_object(tree,idx)
@specialize

"""
	get_parent(n::AbstractNode)

Return the parent of a given node
"""
get_parent(n::AbstractNode;tree=get_tree()) = get_node(n,n.parentID)
get_parent(tree::AbstractTree) = tree

"""
	remove_all_child(n::Node)

Remove all the childs of a Node `n`
"""
function remove_all_children(n::Node)
	childrenID = getfield(n,:childrens)
	tree = get_tree(n).value

	for i in reverse(childrenID)
		
		child = tree.objects[childrenID[i]]
		!is_leave(child) && remove_all_children(child)

		tree.node_count -= 1
		delete!(tree,childrenID[i])
	end

	empty!(childrenID)
end

"""
	remove_child(n,n2::AbstractNode)

Will remove the Node `n2` from childrens of `n`.
"""
remove_child(n,n2::AbstractNode) = begin
	childrenID = getfield(n,:childrens)
	tree = get_tree(n).value
	
	for i in eachindex(childrenID)
		if childrenID[i] == get_nodeidx(n2)

			child = tree.objects[childrenID[i]]
			remove_all_children(child)
			delete!(tree,childrenID[i])
			deleteat!(childrenID,i)
			tree.node_count -= 1

			return
		end
	end
end
remove_child(n,i::Integer) = begin
	childrenID = getfield(n,:childrens)
	tree = get_tree(n).value

	child = tree.objects[childrenID[i]]
	remove_all_children(child)
	delete!(tree,childrenID[i])
	deleteat!(childrenID,i)
	tree.count -= 1
end

"""
	remove_node(tree::AbstractTree,n2::AbstractNode)

Will remode the node `n2` from `tree`.
"""
remove_node(tree::AbstractTree,n2::AbstractNode) = remove_child(get_parent(n2),n2;tree=tree)

"""
	get_tree()

Return the current active tree. You will have to redefine this in your projects with `NodeTree.get_tree() = Your_tree`
"""
@inline get_tree() = nothing
get_tree(n::Node) = getfield(n,:tree)
get_tree(r::ObjectRoot) = getfield(r,:tree)

get_object(tree::ObjectTree,id::Integer) = id == -1 ? tree : tree.objects[id]

"""
	get_object_count(tree::ObjectTree)

Return the number of object present in the ObjectTree `tree`
"""
get_object_count(tree::ObjectTree) = getfield(tree,:node_count)

"""
	get_root(tree::AbstractTree)

Return the root of a tree.
"""
@noinline get_root(tree::AbstractTree) = getfield(tree,:root)

"""
	get_leaves(tree::AbstractTree)

return an iterator of leaves of the AbstractTree `tree`.
"""
@noinline function get_leaves(node;leaves=[],abort=false,filters = nothing)
	
	for child in get_children(node)
		if is_leave(child)
			push!(leaves,child)
		else
			get_leaves(child;leaves=leaves,abort=true)
		end
	end

	!abort && (filters != nothing && filter!(filters,leaves);
				return leaves)
end
function get_leaves(tree::AbstractTree;filters = nothing)
	leaves = []
	childrens = tree.objects

	for child in childrens
		is_leave(child) && push!(leaves,child)
	end

	return leaves
end

function merge_tree!(t1::ObjectTree, t2::ObjectTree)
	for i in 1:length(t2.objects)
		k, v = getfield(t2.objects, :ky)[i], getfield(t2.objects, :vl)[i]
		v.tree = WeakRef(t1)
		t1.objects[k] = v
		push!(t1.root.childs, k)
	end

	t1.node_count += length(t2.objects)

end

get_free_indice(tree::ObjectTree) = isempty(tree.free_indices) ? get_object_count(tree) : pop!(tree.free_indices)

"""
	nvalue(x)

Return the value of a node
"""
nvalue(n::Node) = getfield(n,:self)

Base.getindex(n::AbstractNode) = nvalue(n)

Base.setindex!(n::Node,v) = setfield!(n,:self,v)

"""
	add_child(n::AbstractNode,obj)

Use this to add a child to an AbstractNode.
"""
function add_child(n::Node,n2::Node)

    tree = get_tree(n).value
    tree.node_count += 1
	id = get_free_indice(tree)

	push!(getfield(n,:childrens),id)

	setfield!(n2,:tree,WeakRef(tree))
	setfield!(n2,:parentID,get_nodeidx(n))

    if id >= tree.node_count
	    push!(tree.objects, n2)
	else 
		tree.objects[id] = n2
    end
	set_nodeidx(n2,id)
end
function add_child(tree::ObjectTree,N::Node)
	tree.node_count += one(UInt)

	ID = get_free_indice(tree)
	root = get_root(tree)
	push!(root.childs,ID)

	N.tree = WeakRef(tree)
    if ID >= tree.node_count
	    push!(tree.objects, N)
	else 
		tree.objects[ID] = N
    end
	set_nodeidx(N,ID)
end
add_child(tree::AbstractTree,obj;name=_generate_node_name()) = add_child(tree,Node(obj,name))
@inline add_child(n::Node,obj,name=_generate_node_name()) = add_child(n,Node(obj,name))

"""
	get_siblings(n::Node)

Return all the Nodes with the same parent as `n`.
"""
get_siblings(n::Node) = get_children(get_parent(n);except=(get_nodeidx(n),))


@inline function BFS_search(a;iter=[],abort=false)
	push!(iter,a)

	for elt in a
		if is_leave(elt)
			push!(iter,elt)
		else
			BFS_search(elt;iter=iter,abort=true)
		end
	end

	!abort && return iter
end
@inline function BFS_search(tree::AbstractTree)
	iter = []
	root = get_root(tree)
	childrens = get_children(root)
	for child in childrens
		push!(iter,child)
		BFS_search(child;iter=iter,abort=true)
	end

	return iter
end
@inline function BFS_search(n::AbstractNode;iter=[],abort=false)
	childrens = get_children(n)
	for child in childrens
		push!(iter,child)
		BFS_search(child;iter=iter,abort=true)
	end

	!abort && return iter
end

@inline function DFS_search(a;iter=[],abort=false)
	for elt in a
		if is_leave(elt)
			push!(iter,elt)
		else
			DFS_search(elt,iter=iter,abort=true)
		end
	end

	push!(iter,a)

	!abort && return iter
end
DFS_search(tree::AbstractTree) = DFS_search(get_children(get_root(tree)))

_clean_children(n::Node) = begin

	tree = get_tree(n).value
	childrenID = getfield(n,:childrens)

	@inbounds for i in eachindex(childrenID)
		condition = (getfield(tree,:objects)[childrenID[i]] == nothing)
		if condition
			deleteat!(childrenID,i)
		end
	end
end

precompile(get_node,(Node,Tuple))
precompile(get_node,(ObjectRoot,Tuple))
precompile(get_child,(Any,Int))
precompile(add_child,(Node,Node))
precompile(BFS_search,(ObjectTree,))
precompile(BFS_search,(Node,Vector,Bool))
