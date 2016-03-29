### Keysight / Agilent E8257D
module E8257DModule

import Base: getindex, setindex!

## Import packages
import VISA

## Import our modules
importall PainterQB                 # All the stuff in InstrumentDefs, etc.
metadata = insjson(joinpath(Pkg.dir("PainterQB"),"deps/E8257D.json"))

export E8257D

export OutputSettled
export SetFrequencyReference
export SetPhaseReference

export boards, cumulativeattenuatorswitches, cumulativepowerons, cumulativeontime
export options, revision

"Concrete type representing an E8257D."
type E8257D <: InstrumentVISA
    vi::(VISA.ViSession)
    writeTerminator::ASCIIString
    model::AbstractString
    E8257D(x) = begin
        ins = new()
        ins.vi = x
        ins.writeTerminator = "\n"
        ins.model = "E8257D"
        VISA.viSetAttribute(ins.vi, VISA.VI_ATTR_TERMCHAR_EN, UInt64(1))
        ins
    end

    E8257D() = new()
end

"Has the output settled?"
abstract OutputSettled           <: InstrumentProperty
abstract SetFrequencyReference   <: InstrumentProperty
abstract SetPhaseReference       <: InstrumentProperty

returntype(::Type{Bool}) = (Int, Bool)
returntype(::Type{Real}) = (Float64, Float64)
returntype(::Type{Integer}) = (Int, Int)
fmt(v::Bool) = string(Int(v))
fmt(v) = string(v)

generate_all(E8257D, metadata)

boards(ins::E8257D) = ask(ins,"DIAGnostic:INFOrmation:BOARds?")

cumulativeattenuatorswitches(ins::E8257D) =
    ask(ins,"DIAGnostic:INFOrmation:CCOunt:ATTenuator?")

"Returns the number of attenuator switching events over the instrument lifetime."
cumulativeattenuatorswitches

cumulativepowerons(ins::E8257D) = ask(ins,"DIAGnostic:INFOrmation:CCOunt:PON?")

"Returns the number of power on events over the instrument lifetime."
cumulativepowerons

cumulativeontime(ins::E8257D) = ask(ins,"DIAGnostic:INFOrmation:OTIMe?")

"Returns the cumulative on-time over the instrument lifetime."
cumulativeontime

function options(ins::E8257D; verbose=false)
    if verbose
        ask(ins,"DIAGnostic:INFOrmation:OPTions:DETail?")
    else
        ask(ins,"DIAGnostic:INFOrmation:OPTions?")
    end
end

"Reports the options available for the given E8257D."
options

revision(ins::E8257D) = ask(ins,"DIAGnostic:INFOrmation:REVision?")

"Reports the revision of the E8257D."
revision

setfrequencyref(ins::E8257D) = write(ins, "SOURce:FREQuency:REFerence:SET")
setphaseref(ins::E8257D) = write(ins, "SOURce:PHASe:REFerence")
settled(ins::E8257D) = Bool(parse(ask(ins, ":OUTPut:SETTled?"))::Int)


end
