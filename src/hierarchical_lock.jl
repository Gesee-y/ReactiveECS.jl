##########################################################################################################################
################################################## HIERARCHICAL LOCK #####################################################
##########################################################################################################################

module HierarchicalLocks

export HierarchicalLock, LockNode

######################################################## CORE ############################################################

"""
    mutable struct LockNode{T}
		children::Dict{Symbol, LockNode}
	    locked::Bool
		lck::ReentrantLock

Represent a sub tree of lock for the type `T`.
`children` match every `field` of `T` to a another subtree.
`locked` is wheter a `lock` is acquired for this node or not.
`lck` is the lock of the node. Only leaves (`LockNode`s from types with no field) have this field initialized.

## Constructor

    LockNode{T}() where T <: DataType

This will contruct a subtree of `LockNode` for the type `T`.
"""
mutable struct LockNode{T}
	children::Dict{Symbol, LockNode}
    locked::Bool
	lck::ReentrantLock

	## Constructors

	function LockNode{T}() where T
		dict = Dict{Symbol, LockNode}()
		
		if _has_no_field(T)
			ln = new{T}(dict, false, ReentrantLock())
			
			for field in fieldnames(T)
				t = fieldtype(T, field)
				dict[field] = LockNode{t}()
			end

			return ln
		else
			return new{T}(dict, false)
		end
	end
end

"""
    struct HierarchicalLock{T}
    	root::LockNode

A tree of `LockNode`.
"""
struct HierarchicalLock{T}
	root::LockNode{T}

	## Constructor

	HierarchicalLock{T}() where T = new{T}(LockNode{T}())
end

####################################################### Functions ########################################################

"""
    get_children(hl::HierarchicalLock)

Return a tuple just containing the root node of the hierarchy of locks.

    get_children(ln::LockNode)

Return an iterator (`ValueIterator`) on the children of `ln`.
If `is_leave(ln::LockNode)` is true, then it returns an empty tuple. 
"""
get_children(hl::HierarchicalLock) = (hl.root,)
get_children(ln::LockNode) = is_leave(ln) ? () : values(ln.children)

"""
    get_node(ln::LockNode, path)

Will return the `LockNode` at `path` starting at `ln`.
`path` is an iterator of symbols where each one is a field of the subsequent one.
"""
function get_node(ln::LockNode, path)
	current_node = ln
	for symb in path
		current_node = current_node.children[symb]
	end

	return current_node
end

"""
    is_leave(ln::LockNode{T})

Return whether the `T` has no field, meaning `ln` has no child `LockNode`
"""
is_leave(ln::LockNode) = isdefined(ln, :lck)

"""
    lock(ln::LockNode, path)

Lock the node at `path`, starting from `ln`.
`path` is an iterator of symbol, each should be a field of subsequent type

    lock(f::Function, ln::LockNode, path)

This will lock the node `ln` at `path`, execute `f`, then unlock `ln`.

    lock(hl::HierarchicalLock, path)

This will lock the root `LockNode` at `path`

    lock(f::Function, hl::HierarchicalLock, path)

This will lock `ln` at `path`, execute `f` then unlock `ln` at `path.
"""
Base.lock(hl::HierarchicalLock, path) = lock(hl.root, path)
Base.lock(f::Function, hl::HierarchicalLock, path) = lock(f, hl.root, path)
Base.lock(ln::LockNode) = _func_at(lock, ln, path)
Base.lock(ln::LockNode, path) = lock(get_node(ln,path))
Base.lock(f::Function, ln::LockNode) = (lock(ln); f(); unlock(ln))
Base.lock(f::Function, ln::LockNode, path) = (node=get_node(ln,path);lock(node, path); f(); unlock(node, path))

"""
    unlock(ln::LockNode, path)

This will unlock `ln` at `path`.
If the lock has been acquired multiple times, it will just decrement an internal counter.
"""
Base.unlock(hl::HierarchicalLock, path) = unlock(hl.root, path)
Base.unlock(ln::LockNode) = _func_at(unlock, ln)
Base.unlock(ln::LockNode, path) = unlock(get_node(ln, path))

"""
    islocked(ln::LockNode) -> Status (Bool)

Return true if the `LockNode` `ln` is held by any task/thread.

    Base.islocked(ln::LockNode, path) -> Status (Bool)

Return true if the `LockNode` at `path` starting from `ln` is held by any task/thread.
"""
Base.islocked(ln::LockNode) = ln.locked
Base.islocked(ln::LockNode, path) = (node=get_node(ln, path); return node.locked)

"""
    trylock(ln::LockNode, path) -> Success (Bool)

This will try acquiring the lock at `path` if `islocked(ln::Lock)` is `false`.
"""
function Base.trylock(ln::LockNode, path)::Bool
	success = !islocked(ln)

	if success
		lock(ln, path)
	end

	return success
end

####################################################### Helpers #########################################################

_has_no_field(T::Type) = isempty(fieldnames(T))
function _func_at(func,ln::LockNode; locked=false)

	is_leave(ln) ? func(ln.lck) : _func_all(func, ln)
	ln.locked = locked
end

function _func_all(f,func,ln::LockNode; locked=false)
	if is_leave(ln)
		func(f,ln.lck)
	else
		for child in get_children(ln)
			_func_all(child;locked=locked)
	    end
	end
	ln.locked = locked
end

end # module