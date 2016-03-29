import JSON

export insjson
export generate_all
export generate_types, generate_handlers, generate_configure, generate_inspect
export argsym, argtype, insjson, stripin

"""
`insjson{T<:Instrument}(::Type{T})`

Simple wrapper to call `insjson` on the appropriate file path for a given
instrument type.
"""
function insjson{T<:Instrument}(::Type{T})
    # Get the name of the instrument by taking the type name (without module prefixes!)
    insname = split(string(T.name),".")[end]
    insjson(insname*".json")
end

"""
`insjson(file::AbstractString)`

Parses a JSON file with a standardized schema to describe how to control
an instrument.

Here is an example of a valid JSON file with valid schema for parsing:

```json
{
    "properties":[
        {
            "cmd":":CALCch:TRACtr:CORR:EDEL:TIME",
            "type":"VNA.ElectricalDelay",
            "values":[
                "v::Real"
            ],
            "infixes":[
                "ch::Integer=1",
                "tr::Integer=1"
            ],
            "doc": "My documentation"
        }
    ]
}
```

- `cmd`: Specifies what must be sent to the instrument (it should be
terminated with "?" for query-only). The lower-case characters are replaced
by infix arguments.
- `type`: Specifies the `InstrumentProperty` subtype to use this command. Will be
parsed and evaluated.
- `values`: Specifies the required arguments for `setindex!` which will
appear after `cmd` in the string sent to the instrument.
- `infixes`: Specifies the infix arguments in `cmd`. Symbol names must match
infix arguments.
- `doc`: Specifies documentation for the generated Julia functions.
"""
function insjson(file::AbstractString)
    j = JSON.parsefile(file)

    # Prefer symbols as keys instead of strings
    j = convert(Dict{Symbol,Any}, j)

    !haskey(j, :properties) && error("Unexpected format in JSON file.")

    # Tidy up (and validate?) the properties dictionary
    for i in eachindex(j[:properties])
        # Prefer symbols instead of strings
        j[:properties][i] = convert(Dict{Symbol,Any}, j[:properties][i])
        p = j[:properties][i]
        p[:type] = parse(p[:type])

        p[:values] = convert(Array{Expr,1}, map(parse, p[:values]))

        !haskey(p, :infixes) && (p[:infixes] = [])
        !haskey(p, :doc) && (p[:doc] = "Undocumented.")
        p[:infixes] = convert(Array{Expr,1}, map(parse, p[:infixes]))
        for k in p[:infixes]
            # `parse` doesn't recognize we want the equal sign to indicate
            # an optional argument, denoted by the :kw symbol.
            k.head = :kw
        end
    end

    j
end


"""
`argtype(expr)`

Given function arguments, will return types:

- `:(x::Integer)` → `Integer`
- `:(x::Integer=3)` → `Integer`
- `:(x)` → `Any`
- `:(x=3)` → `Any`

Some package-specific cases:

- `:(x in symbols)` → `Any`
- `:(x::Symbol in symbols)` → `Symbol`
"""
function argtype(expr)
    if isa(expr, Symbol)
        return Any
    elseif expr.head == :(::)
        if length(expr.args) == 1
            return eval(expr.args[1])
        else
            return eval(expr.args[2])
        end
    elseif expr.head == :(=) || expr.head == :(kw) || expr.head == :(in)
        return argtype(expr.args[1])
    else
        error("Cannot handle this argument.")
    end
end

"""
`argsym(expr)`

Given function arguments, will return symbols:

- `:(x::Integer)` → `:x`
- `:(x::Integer=3)` → `:x`
- `:(x)` → `:x`
- `:(x=3)` → `:x`

Some package-specific syntax:

- `:(x in symbols)` → `:x`
- `:(x::Symbol in symbols)` → `:x`
"""
function argsym(expr)
    if isa(expr, Symbol)
        return expr
    elseif expr.head == :(::)
        if length(expr.args) == 1
            return :_
        else
            return expr.args[1]
        end
    elseif expr.head == :(=) || expr.head == :(kw) || expr.head == :(in)
        return argsym(expr.args[1])
    else
        error("Cannot handle this argument.")
    end
end

"""
`stripin(expr)`

Return the same expression in most cases, except:

- `:(x::Symbol in symbols)` → `:(x::Symbol)`
- `:(x in symbols)` → `:x`
"""
function stripin(expr)
    isa(expr, Symbol) && return expr
    if expr.head == :(in)
        return expr.args[1]
    else
        return expr
    end
end

function generate_all{S<:Instrument}(ins::Type{S}, metadata)
    for p in metadata[:properties]
        generate_types(ins, p)
        generate_handlers(ins, p)
        generate_inspect(ins, p)
        if p[:cmd][end] != '?'
            generate_configure(ins, p)
        end
    end
end

"""
`generate_types{S<:Instrument}(instype::Type{S}, p)`

This function takes an `Instrument` subtype `instype`, and a property dictionary
`p`. The property dictionary is built out of an auxiliary JSON file described above.

This function is responsible for generating the `InstrumentProperty` subtypes
to use with `getindex` and `setindex!` if they have not been defined already.
Ordinarily these types are defined in the PainterQB module but if a really
generic name is desired that makes sense for a class of instruments (e.g. `VNA.Format`)
then the `Format` subtype is defined in the `PainterQB.VNA` module. The defined
subtype is then imported into the module where the `instype` is defined.

"""
function generate_types{S<:Instrument}(instype::Type{S}, p)
    md = instype.name.module
    if isa(p[:type], Symbol)
        # No module path; assume we define it in the base module
        if !isdefined(PainterQB, p[:type])
            # Define and export the InstrumentProperty subtype in PainterQB
            eval(PainterQB, :(abstract $(p[:type]) <: InstrumentProperty))
            eval(PainterQB, :(export $(p[:type])))
            # Import the subtype in our instrument's module
            eval(md, :(import PainterQB.$(p[:type])))
        end
    elseif isa(p[:type], Expr)
        # Symbol is qualified by module path.
        sym = p[:type].args[2].value
        where = eval(p[:type].args[1])
        if !isdefined(where, sym)
            # Define and export the InstrumentProperty subtype in PainterQB
            eval(where, :(abstract $sym <: InstrumentProperty))
            eval(where, :(export $sym))
            # We need to take care with module paths. The following is
            # kind of crude but import doesn't accept modules, only symbols
            syms = map(symbol, split(string(p[:type]),"."))
            syms[1] != :PainterQB && (insert!(syms, 1, :PainterQB))
            # Import the subtype in our instrument's module
            eval(md, Expr(:import, syms...))
        end
    else
        # Parser found something weird
        error("Unexpected InstrumentProperty subtype name.")
    end
end

"""
`generate_handlers{S<:Instrument}(instype::Type{S}, p)`

This function takes an `Instrument` subtype `instype`, and a property dictionary
`p`. The property dictionary is built out of an auxiliary JSON file described above.

In some cases, an instrument command does not except numerical arguments but
rather a small set of options. Here is an example of the JSON template for such
a command, which sets/gets the format for a given channel and trace on the E5071C
vector network analyzer:

```json
{
    "cmd":":CALCch:TRACtr:FORM",
    "type":"VNA.Format",
    "values":[
        "v::Symbol in symbols"
    ],
    "symbols":{
        "LogMagnitude":"MLOG",
        "Phase":"PHAS",
        "GroupDelay":"GDEL",
        "SmithLinear":"SLIN",
        "SmithLog":"SLOG",
        "SmithComplex":"SCOM",
        "Smith":"SMIT",
        "SmithAdmittance":"SADM",
        "PolarLinear":"PLIN",
        "PolarLog":"PLOG",
        "PolarComplex":"POL",
        "LinearMagnitude":"MLIN",
        "SWR":"SWR",
        "RealPart":"REAL",
        "ImagPart":"IMAG",
        "ExpandedPhase":"UPH",
        "PositivePhase":"PPH"
    },
    "infixes":[
        "ch::Integer=1",
        "tr::Integer=1"
    ],
    "doc":"Hey"
}
```

We see here that the `values` key is saying that we are only going to accept
`Symbol` type for our `setindex!` method and the symbol has to come out of `symbols`,
a dictionary that is defined on the next line. The keys of this dictionary
are going to be interpreted as symbols (e.g. `:LogMagnitude`) and the values
are just ASCII strings to be sent to the instrument.

`generate_handlers` makes a bidirectional mapping between the symbols and the strings.
In this example, this is accomplished as follows:

```jl
symbols(ins::E5071C, ::Type{VNA.Format}, v::Symbol) = symbols(ins, VNA.Format, Val{v})
symbols(ins::E5071C, ::Type{VNA.Format}, ::Type{Val{:LogMagnitude}}) = "MLOG" # ... etc. for each symbol.

VNA.Format(ins::E5071C, s::AbstractString) = VNA.Format(ins, Val{symbol(s)})
VNA.Format(ins::E5071C, ::Type{Val{symbol("MLOG")}}) = :LogMagnitude # ... etc. for each symbol.
```

The above methods will be defined in the E5071C module. Note that the function `symbols`
has its name chosen based on the dictionary name in the JSON file. This was done
for future flexibliity.
"""
function generate_handlers{S<:Instrument}(instype::Type{S}, p)

    md = instype.name.module
    T = eval(md, p[:type])

    # Look for symbol dictionaries
    for v in p[:values]
        if v.head == :(in)
            # Looks like we have a dictionary of symbols
            sym = v.args[2]     # name of dictionary
            !haskey(p, sym) && error("Property $p lacking some information.")
            dict = p[sym]       # the dictionary

            # Define methods to dispatch based on Val types
            # e.g. symbols(ins::AWG5014C, ::Type{ClockSource}, v::Symbol) =
            #       symbols(ins, ClockSource, Val{v})
            # and  ClockSource(ins::AWG5014C, s::AbstractString) =
            #       ClockSource(ins, Val{symbol(s)})
            eval(md, :(($sym)(ins::$instype, ::Type{$T}, $(v.args[1])) =
                ($sym)(ins, $T, Val{$(argsym(v))})))
            eval(md, :(($(p[:type]))(ins::$instype, s::AbstractString) =
                ($(p[:type]))(ins, Val{symbol(s)})))

            # Now define the methods that use the Val types
            # e.g. symbols(ins::AWG5014C, ::Type{ClockSource}, Val{:Internal}) = "INT"
            # and  ClockSource(ins::AWG5014C, Val{:INT}) = :Internal
            for (a,b) in dict
                eval(md, :(($sym)(ins::$instype, ::Type{$T}, ::Type{Val{parse($a)}}) = $b))
                eval(md, :(($(p[:type]))(ins::$instype, ::Type{Val{symbol($b)}}) = parse($a)))
            end
        end
    end

    nothing
end

"""
`generate_inspect{S<:Instrument}(instype::Type{S}, p)`

This function takes an `Instrument` subtype `instype`, and a property dictionary
`p`. The property dictionary is built out of an auxiliary JSON file described above.

This function generates and documents a method for `getindex`. The method is
defined in the module where the instrument type was defined.
"""
function generate_inspect{S<:Instrument}(instype::Type{S}, p)

    # Get the instrument property type and assert.
    md = instype.name.module
    T = eval(md, p[:type])
    !haskey(p, :infixes) && (p[:infixes] = [])

    # Collect the arguments for `inspect`
    fargs = [:(ins::$S), :(::Type{$T})]
    for a in p[:infixes]
        push!(fargs, a)
    end

    # If it looks like configure needs two or more parameters to follow the
    # command, the return type for inspect is not obvious
    length(p[:values]) > 1 && error("Not yet implemented.")

    # Begin constructing our definition of `inspect`
    method  = Expr(:call, :getindex, fargs...)
    inspect = Expr(:function, method, Expr(:block))
    fbody = inspect.args[2].args

    # Add the question mark for a query
    command = p[:cmd]
    command[end] != '?' && (command *= "?")

    # In the function body: Define `cmd`
    push!(fbody, :(cmd = $command))

    # In the function body: Replace the infixes with the `getindex` arguments
    for infix in p[:infixes]
        sym = argsym(infix)
        name = string(sym)
        push!(fbody, :(cmd = replace(cmd, $name, $sym)))
    end

    if p[:values][1].head != :(in)
        vtyp = argtype(p[:values][1])
        if vtyp <: Number
            P,C = md.returntype(vtyp)
            push!(fbody, :(($C)(parse(ask(ins, cmd))::($P))) )
        else
            push!(fbody, :(ask(ins, cmd)) )
        end
    else
        push!(fbody, :(($T)(ins, ask(ins, cmd))))
    end

    # Define the method in the current module.
    eval(md, inspect)

    # Document the method.
    p[:doc] = string("```jl\n",method,"\n```\n\n") * "\n\n" * p[:doc]  # Prepend with method signature
    eval(md, :(@doc $(p[:doc]) $method))             # ...and document it.

    # Return a method signature without variable names, optional argument defaults, etc.
    method # = Expr(:call, :getindex, map(typesig, fargs)...)
end

"""
`generate_configure{S<:Instrument}(instype::Type{S}, p)`

This function takes an `Instrument` subtype `instype`, and a property dictionary
`p`. The property dictionary is built out of an auxiliary JSON file described above.

This function generates and documents a method for `getindex`. The method is
defined in the module where the instrument type was defined.
"""
function generate_configure{S<:Instrument}(instype::Type{S}, p)

    # Get the instrument property type and assert.
    md = instype.name.module
    T = eval(md, p[:type])

    command = p[:cmd]
    !haskey(p, :infixes) && (p[:infixes] = [])

    length(p[:values]) > 1 && error("Not yet implemented.")

    method = Expr(:call, :setindex!,
        :(ins::$S), map(stripin, p[:values])..., :(::Type{$T}), p[:infixes]...)

    configure = Expr(:function, method, Expr(:block))
    fbody = configure.args[2].args

    # In the function body: Define `cmd`
    push!(fbody, :(cmd = $(command*" #")))
    for infix in p[:infixes]
        sym = argsym(infix)
        name = string(sym)
        push!(fbody, :(cmd = replace(cmd, $name, $sym)))
    end

    if p[:values][1].head == :(in)
        dictname = p[:values][1].args[2]
        push!(fbody, :(write(ins, cmd, ($dictname)(ins, $T, $(argsym(p[:values][1]))))))
    else
        vsym = argsym(p[:values][1])
        push!(fbody, :(write(ins, cmd, fmt($vsym))))
    end

    # Define the method in the current module.
    eval(md, configure)

    # Document the method.
    p[:doc] = string("```jl\n",method,"\n```\n\n") * "\n\n" * p[:doc]  # Prepend with method signature
    eval(md, :(@doc $(p[:doc]) $method))             # ...and document it.

    method  # = Expr(:call, :setindex!, :(::$S),
    #    map(typesig, p[:values])..., :(::Type{$T}), map(typesig, p[:infixes])...)
end

# If you want to generate method signatures explicitly in the docs...
#
# typesig(expr) = Expr(:(::), symbol(argtype(expr)))
#
# function generate_all{S<:Instrument}(ins::Type{S})
#     g,s,b = generate_docs_template(ins)
#     open(g, "a") do io
#         for p in metadata[:properties]
#             generate_handlers(ins, p)
#             method = generate_inspect(ins, p)
#             write(io, "\t$method\n")
#         end
#     end
#     open(s, "a") do io
#         for p in metadata[:properties]
#             if p[:cmd][end] != '?'
#                 method = generate_configure(ins, p)
#                 write(io, "\t$method\n")
#             end
#         end
#     end
# end
#
# function generate_docs_template{S<:Instrument}(ins::Type{S})
#     name = lowercase(split(string(ins.name),".")[end])
#     base = joinpath(Pkg.dir("PainterQB"),"docs","src",name)
#     gpath = joinpath(base, "getindex.md")
#     spath = joinpath(base, "setindex.md")
#     bpath = joinpath(base, "body.md")
#     for p in (gpath, spath)
#         open(p, "w") do io
#             # write(io, "\t{index}\n\n")
#             write(io, "\t{docs}\n")
#         end
#     end
#     gpath, spath, bpath
# end