export DelayStimulus, TimerResponse, TimeAResponse

"""
When sourced with a value in seconds, `DelayStimulus` will wait until that many
seconds have elapsed since the DelayStimulus was initialized.
"""
type DelayStimulus <: Stimulus
	t0::AbstractFloat
end

"""
When measured, `TimerResponse` will return how many seconds have elapsed since
the timer was initialized.
"""
type TimerResponse{T<:AbstractFloat} <: Response{T}
	t0::T
end

"""
When measured, `TimeAResponse` will return how many seconds it takes to measure
the response field it holds. So meta.
"""
type TimeAResponse <: Response{typeof(time())}
    r::Response
end

TimerResponse() = TimerResponse(time())
DelayStimulus() = DelayStimulus(time())

function source(ch::DelayStimulus, val::Real)
	if val < eps()
		ch.t0 = time()
	else
		while val + ch.t0 > time()
			sleep(0.01)
		end
	end
end

measure{T}(ch::TimerResponse{T}) = T(time()) - ch.t0

measure(ch::TimeAResponse) = begin
    t0 = time()
    measure(ch.r)
    time()-t0
end
