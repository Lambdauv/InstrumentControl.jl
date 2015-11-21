export Instrument

"""
### Instrument
`abstract Instrument <: Any`

Abstract supertype of all concrete Instrument types, e.g.
`AWG5014C <: Instrument`.
"""
abstract Instrument

# Define common types and shared functions
include("InstrumentDefs.jl")

# Define some functions to programmatically generate
# functions for VISA instruments
include("Metaprogramming.jl")

# Define anything needed for a VISA instrument
include("InstrumentVISA.jl")
