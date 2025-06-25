## ---------------------- Linked Node --------------------- ##

export LNode, LinkedRoot, LinkedTree

"""
	struct LNode{T} <: AbstractNode
		self :: T
		idx :: Tuple
		tree :: WeakRef

		name :: String
		childrens :: Vector{LNode}

A struct to create a LNode (which stands for `LinkedNode`.) for a LinkedTree.
Nodes are just envelops for objects in the tree. They just serve as a container.

## Constructors

	LNode(obj,name=_generate_node_name();index=1)

Construct a new `LNode` based on the object `obj`. `name` is how the node will be named.
`index` is the default index of the node
"""
mutable struct LNode{T} <: AbstractNode
	self :: T
	idx :: Tuple
	tree :: WeakRef

	name :: String
	childrens :: Vector{LNode}

	LNode(obj,name=_generate_node_name();index=1) = new{typeof(obj)}(obj,(index,),WeakRef(nothing),name,LNode[])
	LNode{T}(obj::T,name=_generate_node_name();index=1) where T= new{T}(obj,(index,),WeakRef(nothing),name,LNode[])
end

"""
	struct LinkedRoot <: AbstractRoot
		childs :: Vector{LNode}

A structure to use as a root for a LinkedTree. He his the one containing all the root node (
the node at the base of the tree.).

## Constructors

	`LinkedRoot()`

Will create a new empty root.

	LinkedRoot(childs::Vector{LNode})

will create a new LinkedRoot from a set of vector.
"""
struct LinkedRoot <: AbstractRoot
	childs :: Vector{LNode}

	LinkedRoot() = new(LNode[])
	LinkedRoot(childs::Vector{LNode}) = new(childs)
end

"""
	struct LinkedTree <: AbstractTree
		root :: LinkedRoot

This struct represent a linked tree, in which node are all linked together to form the tree.

## Constructors

	LinkedTree()

Construct a new `LinkedTree` object.

	LinkedTree(root::LinkedRoot)

Construct a new `LinkedTree` object from an existing root
"""
struct LinkedTree <: AbstractTree
	root :: LinkedRoot

	LinkedTree() = new(LinkedRoot())
	LinkedTree(root::LinkedRoot) = new(root)
end

include("Loperations.jl")