#####################################################################################################################
################################################# FRAGMENT ARRAYS ###################################################
#####################################################################################################################

"""
    module FragmentArrays

This module implement fragmenting arrays, whose are arrays that divide themself on deletions
Kinda like sparse arrays.
"""
module FragmentArrays

## Core data structures
include("core.jl")
## Layout interface
include("layout.jl")
## Indexing
include("indexing.jl")
## Common operations
include("operations.jl")

end # module