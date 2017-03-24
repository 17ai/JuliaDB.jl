module JuliaDB

using IndexedTables, Dagger, NamedTuples

import IndexedTables: Table

# re-export
export IndexedTable, Columns

include("util.jl")
include("interval.jl")
include("dtable.jl")
include("load.jl")
include("load-save.jl")
include("printing.jl")
include("dcolumns.jl")

include("indexing.jl")
include("query.jl")

end # module
