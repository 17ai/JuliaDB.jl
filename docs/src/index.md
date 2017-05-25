```@meta
CurrentModule = JuliaDB
```

# Overview

**JuliaDB is a package for working with large persistent data sets.** We recognized the need for a convenient, end-to-end tool to load common multi-dimensional datasets quickly, perform filter, aggregation, sort and join operations on them and save the results efficiently for later. We also wanted the tool to readily make use of Julia's built-in parallelism to acheive close to the best performance on any machine or cluster. This is the motivation behind JuliaDB.

JuliaDB is Julia all the way down. This means queries can be composed with Julia code that may use its vast ecosystem of packages, incurring no overhead as computation reaches the data.

JuliaDB is based on [Dagger](https://github.com/JuliaParallel/Dagger.jl) and [IndexedTables](https://github.com/JuliaComputing/IndexedTables.jl), providing a array-like data model where the indices of the array are themselves data. Over time, we hope to expand this to include dense arrays and other Julia array types like [`AxisArrays`](https://github.com/JuliaArrays/AxisArrays.jl). JuliaDB also provides all the familiar relational database operations that are optimized to use the indexed nature of the data model.

Given a set of CSV files, JuliaDB builds and saves an index that allows the data to be accessed efficiently in the future. The "ingest" operation converts data to an efficient memory-mappable binary format. We plan to extend JuliaDB to use data from various other sources.

# Installation

JuliaDB works on Julia 0.6 or higher. To install it, run:

```julia
Pkg.clone("https://github.com/JuliaComputing/JuliaDB.jl.git")
```

# Loading and saving data

## Loading CSV files

To use JuliaDB you may start Julia with a few worker processes, for example, `julia -p 4`. Let's load some sample CSV files that are in JuliaDB's test folder:

```@repl sampledata
using JuliaDB

path = Pkg.dir("JuliaDB", "test", "sample")

sampledata = loadfiles(path, indexcols=["date", "ticker"])
```

`loadfiles` loads all files under a given directory. If you started julia with many processes (e.g. with `julia -p 4`, or by doing `addprocs(N)` before `using JuliaDB`) then `loadfiles` will enlist all available processes to read the csv files in parallel. If you wanted to specify a subset of files to load or files in different directories, you can pass the file names as a vector as in place of the directory path. JuliaDB exports the `glob` function from [Glob.jl](https://github.com/vtjnash/Glob.jl) to help you with this.

Using the `indexcols` option, here we specified that `loadfiles` should use `date` and `ticker` columns as the index for the data. The index columns will be used to sort the data for efficient queries. See [the API reference for `loadfiles`](apireference.html#JuliaDB.loadfiles) for all available options.

Notice that the output says `DTable with 288 rows in 6 chunks`. `loadfiles` creates a distributed table (`DTable`) with as many chunks as the input files. The loaded chunks are distributed across available worker processes. `loadfiles` will also save metadata about the contents of the files in a directory named `.juliadb` in the directory with the files (or in the current working directory if a vector of filenames is passed). This means, the next time the files are loaded, it will not need to actually parse them to know what's in them. However a file will be parsed once an operation requires the data in it.

Another way to load data into JuliaDB is using [`ingest`](@ref ingest). `ingest` reads and saves the data in an efficient memory-mappable binary storage format for faster re-reading. You can also add new files to an existing dataset using [`ingest!`](@ref ingest!).

To set some context, our sample data contains monthly aggregates of stock prices (open, high, low, close values) as well as volume traded for 4 stocks (GOOGL, GS, KO, XRX) in the years 2010 to 2015. Each file contains a single year's data.

## Saving and loading JuliaDB tables

You can save a `DTable` to disk at any point:

```
save(t, "<outputdir>")
```

This will create `<outputdir>` and save the individual chunks of the data separately.

A saved dataset can be loaded with `load`:

```
data = load("<outpudir>")
```

# Filtering

## Indexing

Most lookup and filtering operations on `DTable` can be done via indexing. Our `sampledata` object behaves like a 2-d array, accepting two indices, each values or range of values from the index columns.

You can get a specific value by indexing it by the exact index:

```@repl sampledata
sampledata[Date("2010-06"), "GOOGL"] # Get GOOGL's data for June 2010
```

!!! note
    Note that `Date("2010-06")` is automatically converted to `Date("2010-06-01")`. Since we don't have a Date type which can only represent month and a year (it might be an extraneous abstraction anyway), we have used the first of each month to represent the month itself.

Above, we are indexing the table with a specific index value (`2010-06-01`, `"GOOGL"`). Here our `DTable` behaved like a dictionary, giving the value stored at a given key. The result is a [`NamedTuple`](https://github.com/blackrock/NamedTuples.jl) object containing 5 fields which of the same names as the data columns.

One can also get a subset of the `DTable` by indexing with a range or a sorted vector of index values:

```@repl sampledata
sampledata[:, ["GOOG", "KO"]]
```

Fetches all values in the data for the stock symbols GOOG and KO.

```@repl sampledata
sampledata[Date("2012-01"):Dates.Month(1):Date("2014-12"), ["GOOG", "KO"]]
```

Fetches all values in the data for the stock symbols GOOG and KO in the years 2012 - 2014

Range indexing always returns a `DTable` so that you can apply any other JuliaDB operation on the result of indexing.

Minutiae: notice the range we have used in the last example: `Date("2012-01"):Dates.Month(1):Date("2014-12")`. This says "from 2012-01-01 to 2014-12-01 in steps of 1 month". Date/DateTime ranges in Julia need to be specified with an increment such as `Dates.Month(1)`. If your dataset contains timestamps in the millisecond resolution, for example, you'd need to specify `Dates.Millisecond(1)` as the increment, and so on.

## `select`

If you want to apply a custom predicate on index values to filter the data, you can do so with `select` by passing `column=>predicate` pairs:


```@repl sampledata
select(sampledata, :date=>Dates.ismonday)
```

Filters only data points where the first of the month falls on a monday!

You can also provide multiple predicates. Below we will get values only for months starting on a monday and for stock symbols starting with the letter "G".

```@repl sampledata
select(sampledata, 1=>Dates.ismonday, 2=>x->startswith(x, "G"))
```

`select` is similar to a `where` clause in traditional SQL/relational databases.

## `filter`

`filter` lets you filter based on the data values as opposed to `select` which filters based on the index values.

Here we filter only stock data where either the `low` value is greater than 10.

```@repl sampledata
filter(x->x.low > 10.0, sampledata)
```

Notice the use of `x.low` in the predicate. This is because `x` is a [`NamedTuple`](https://github.com/blackrock/NamedTuples.jl) having the same fields as the columns of the data. If the data columns are not labeled (say because `header_exists` was set to true in `loadfiles` and headers were not manually provided), then the `x` will be a tuple.

# Map and Reduce

Good ol' `map` and `reduce` behave as you'd expect them to. `map` applies a function to every data point in the table. The input to `map` and `reduce` could be either:

- a [`NamedTuple`](https://github.com/blackrock/NamedTuples.jl) - if the data columns are named
- a `Tuple` - if there are multiple columns but the columns are not named
- a scalar value - if there is only one column (a vector) for the data

In this example, we will create a new table that contains the difference between the `high` and `low` value for each point in the table:

```@repl sampledata
diffs = map(x->x.high - x.low, sampledata)
```

!!! note "pick"

    It's often the case that you want to work with a single data vector. Extracting a single column can be acheived by using a simple map.

    ```@repl sampledata
    volumes = map(x->x.volume, sampledata)
    ```

    However, this operation allocates a new data column and then populates it element-wise. This could be expensive. `pick(:volume)` acts as the function `x->x.volume` but is optimized to not copy the data. Hence the above is equivalent to the more efficient version:

    ```@repl sampledata
    volumes = map(pick(:volume), sampledata)
    ```

`reduce` takes a 2-argument function where the arguments are two data values and combines them until there's a single value left. Let's find the sum volume traded for all stocks in our data set

```@repl sampledata
reduce(+, map(x->x.volume, sampledata))
```

Or equivalently,

```@repl sampledata
reduce(+, map(pick(:volume), sampledata))
```

# Aggregation

## `reducedim` and `select`

One way to get a simplified summary of the data is by removing a dimension and then aggregating all values which have a common value.

This can be done by using [`reducedim`](@ref).

```@repl sampledata
function agg_ohlcv(x, y) # hide
    @NT( # hide
        open = x.open, # first # hide
        high = max(x.high, y.high), # hide
        low = min(x.low, y.low), # hide
        close = y.close, # last # hide
        volume = x.volume + y.volume, # hide
    ) # hide
end # hide

@everywhere function agg_ohlcv(x, y)
    @NT(
        open = x.open, # first
        high = max(x.high, y.high),
        low = min(x.low, y.low),
        close = y.close, # last
        volume = x.volume + y.volume,
    )
end

reducedim(agg_ohlcv, sampledata, 1)
```

A few things to note about the `agg_ohlcv` function:

- `agg_ohlcv` takes two data points as NamedTuples, and returns a NamedTuple (constructed using the `@NT` macro) with the exact same fields.
- `open` value of the first input is kept, `high` is calculated as the maximum of high value of both inputs, `low` is the minimum of low values, `close` keeps the value from the second input, `volume` is the sum of volumes of the inputs.
- `agg_ohlcv` function is defined with `@everywhere` - this causes the function to be defined on all worker processes, which is required since the aggregation will be performed on all workers.

Equivalently, the same operation can be done by only `select`ing the 2nd (ticker) dimension.

```@repl sampledata
select(sampledata, 2, agg=agg_ohlcv)
```

If `agg` option is not specified, the result might have multiple values for some indices, and so does not fully behave like a normal array anymore.

Operations that might leave the array in such a state accept the keyword argument `agg`, a function to use to combine all values associated with the same indices.


**`reducedim_vec`**

Some aggregation functions are best written for a vector of data values rather than performed pairwise. Let's calculate the mean of `high-low` difference for each ticker symbol. You can use `reducedim_vec` to do this:

```@repl sampledata
function mean_diff(values) # hide
    mean(map(x->x.high-x.low, values)) # hide
end # hide

@everywhere function mean_diff(values)
    mean(map(x->x.high-x.low, values))
end

reducedim_vec(mean_diff, sampledata, 1)
```

## Aggregation by converting a dimension

A location in the coordinate space of an array often has multiple possible descriptions.
This is especially common when describing data at different levels of detail.
For example, a point in time can be expressed at the level of seconds, minutes, or hours.
In our test dataset, we might want to look at quarterly values.

This can be accomplished using the `convertdim` function. It accepts a `DTable`, a dimension number to convert, a function or dictionary to apply to indices in that dimension, and an aggregation function (the aggregation function is needed in case the mapping is many-to-one). You can optionally give a new name to the converted dimension using the `name` keyword argument.

The following call therefore gives the quarterly aggregates for our data:


```@repl sampledata
convertdim(sampledata, 1, Dates.firstdayofquarter,
                     agg=agg_ohlcv, name=:quarter)
```

The mental model here is, first every value in dimension `1` is converted using the function `Dates.firstdayofquarter`, i.e. to the first day of the quarter that date falls in. Next, the values in the table which correspond to the same indices (e.g. all values for the GOOG stock in 1st quarter of 2010) are aggregated together using `agg`.

# Permuting dimensions

As with other multi-dimensional arrays, dimensions can be permuted to change the sort order of the data. In the context of our sample dataset, interchanging the dimensions would result in the data being sorted first by the stock symbol, and then within each stock symbol, it would be sorted by the date.

```@repl sampledata
permutedims(sampledata, [2, 1])
```

In some cases such dimension permutations are needed for performance. The leftmost column is esssentially the primary key --- indexing is fastest in this dimension.

!!! note
    JuliaDB can perform a distributed sort to keep the resultant data still distributed. Note that this operations can be expensive to do every time you load a dataset (a billion rows take a few minutes to reshuffle), hence it's advisable to do it once and save the result in a separate output directory for re-reading later. (See saving and loading section below).

# Joins

JuliaDB provides several `join` operations to combine two or more `DTable`s into one, namely [`naturaljoin`](@ref), [`leftjoin`](@ref), [`merge`](@ref), and [`asofjoin`](@ref).
