# NodeTree.jl  

A Julia package for tree structures, offering core functionality (search, traversal, etc.) and an interface for creating custom trees.  

## Installation 

```julia-repl
julia> ]add NodeTree
```

or for the development version:  
```julia-repl
julia> ]add https://github.com/Gesee-y/NodeTree.jl
```

## Description  

NodeTree.jl is designed with game development in mind but is versatile enough for other domains. The package provides fully functional tree structures and also natively **treat Julia objects as trees**, eliminating the need for explicit conversion.

## Features  

- **LinkedTree**: Trees where data is wrapped in **node objects** with direct parent-child links.  
- **ObjectTree**: Trees where nodes are stored in a `Dict` and accessed via unique unsigned integer IDs (O(1) lookup).  
- **Traversal functions**: DFS (leaf-to-root) and BFS (root-to-leaf).  
- **Tree manipulation**: Add, remove, and access nodes.  
- **Pretty-printing**: Visualize tree structures, including native Julia types.  
- **Native tree support**: Works with base types (`Array`, `Tuple`, `Dict`, `Pair`, `Expr`) **as trees** without conversion.  
- **Customizable**: Define your own tree types via a simple interface.  

## Usage

```julia
using NodeTree

# Create a new ObjectTree
tree = ObjectTree()

# Redefine the default tree getter for convenience
NodeTree.get_tree() = tree

# Julia arrays are natively treated as trees
a = [[1,2], [3,4]]  

# Create nodes to add to the tree
n1 = Node([1,2,3], "Array")  # Node(value, name) – IDs are auto-managed
n2 = Node([4,5,6], "Array2")
n3 = Node([7,8,9], "Array3")

# Add nodes to the tree
add_child(tree, n1)
add_child(tree, n2)
add_child(tree, n3)

# Add children to node `n1`
n4 = Node(57, "Int Yo")
n5 = Node(789, "Int Yay")
add_child(n1, n4)
add_child(n1, n5)

# Build a subtree under `n2`
n6 = Node(3.4, "Floating")
n7 = Node(rand(), "Floating+")
n8 = Node(rand() * 10, "Floating+++")
n9 = Node(eps(), "Floating+++")
add_child(n2, n6)
add_child(n2, n7)
add_child(n7, n8)
add_child(n2, n9)

# Add a node named "String" to `n3`
n10 = Node("Yay", "String")
add_child(n3, n10)

# Print the ObjectTree structure
print_tree(stdout, tree)

# Print the array `a` as a tree
print_tree(stdout, a)
```

## License  

This package is licensed under MIT. For details, see [License](https://github.com/Gesee-y/NodeTree.jl/blob/main/License.txt).  

## Contribution  

Contributions and bug reports are welcome! Feel free to open issues or submit pull requests.  
