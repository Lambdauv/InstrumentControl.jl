module E8257D
using Compat
import Base: getindex, setindex!
import VISA
importall InstrumentControl     # All the stuff in InstrumentDefs, etc.

returntype(::Type{Bool}) = (Int, Bool)
returntype(::Type{Real}) = (Float64, Float64)
returntype(::Type{Integer}) = (Int, Int)
fmt(v::Bool) = string(Int(v))
fmt(v) = string(v)

@generate_all(InstrumentControl.meta["E8257D"])

export OutputSettled
export SetFrequencyReference
export SetPhaseReference

export boards, cumulativeattenuatorswitches, cumulativepowerons, cumulativeontime
export options, revision

"Has the output settled?"
@compat abstract type OutputSettled           <: InstrumentProperty end
@compat abstract type SetFrequencyReference   <: InstrumentProperty end
@compat abstract type SetPhaseReference       <: InstrumentProperty end


boards(ins::InsE8257D) = ask(ins,"DIAGnostic:INFOrmation:BOARds?")

cumulativeattenuatorswitches(ins::InsE8257D) =
    ask(ins,"DIAGnostic:INFOrmation:CCOunt:ATTenuator?")

"Returns the number of attenuator switching events over the instrument lifetime."
cumulativeattenuatorswitches

cumulativepowerons(ins::InsE8257D) = ask(ins,"DIAGnostic:INFOrmation:CCOunt:PON?")

"Returns the number of power on events over the instrument lifetime."
cumulativepowerons

cumulativeontime(ins::InsE8257D) = ask(ins,"DIAGnostic:INFOrmation:OTIMe?")

"Returns the cumulative on-time over the instrument lifetime."
cumulativeontime

function options(ins::InsE8257D; verbose=false)
    if verbose
        ask(ins,"DIAGnostic:INFOrmation:OPTions:DETail?")
    else
        ask(ins,"DIAGnostic:INFOrmation:OPTions?")
    end
end

"Reports the options available for the given E8257D."
options

revision(ins::InsE8257D) = ask(ins,"DIAGnostic:INFOrmation:REVision?")

"Reports the revision of the E8257D."
revision

setfrequencyref(ins::InsE8257D) = write(ins, "SOURce:FREQuency:REFerence:SET")
setphaseref(ins::InsE8257D) = write(ins, "SOURce:PHASe:REFerence")
settled(ins::InsE8257D) = Bool(parse(ask(ins, ":OUTPut:SETTled?"))::Int)

end
