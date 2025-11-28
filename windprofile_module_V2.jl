using Random, Distributions

##########################################################
# STRUCT
##########################################################

"""
    WindScenario

Holds wind forecast and actual (truth) on the same time grid.
"""
struct WindScenario
    forecast::Vector{Float64}
    actual::Vector{Float64}
    Δt_minutes::Int
end

##########################################################
# BUILD SCENARIO
##########################################################

"""
    build_scenario(wind_forecast; P_rated, σ, ρ)

Generate an actual wind time series by adding AR(1) forecast errors.
"""
function build_scenario(
    wind_forecast::Vector{Float64};
    P_rated::Float64,
    σ::Float64 = 0.05 * P_rated,
    ρ::Float64 = 0.95,
    Δt_minutes::Int = 5,
    rng::AbstractRNG = Random.GLOBAL_RNG,
)

    N = length(wind_forecast)

    # Allocate error sequence
    err = zeros(Float64, N)

    # Innovation noise for AR(1)
    noise = Normal(0.0, σ * sqrt(1 - ρ^2))

    # AR(1) error generation
    err[1] = rand(rng, Normal(0, σ))
    for k in 2:N
        err[k] = ρ * err[k-1] + rand(rng, noise)
    end

    # Construct actual wind profile
    wind_actual = similar(wind_forecast)
    @inbounds for k in 1:N
        wind_actual[k] = clamp(wind_forecast[k] + err[k], 0.0, P_rated)
    end

    return WindScenario(wind_forecast, wind_actual, Δt_minutes)
end

##########################################################
# FORECAST WINDOW FOR MPC
##########################################################

function forecast_window(scen::WindScenario, k::Int, N_h::Int)
    N = length(scen.forecast)

    # Prediction vector
    wind_pred = Vector{Float64}(undef, N_h)

    # 1) First step: actual disturbance
    wind_pred[1] = scen.actual[k]

    # 2) Remaining steps: forecast values
    for i in 2:N_h
        idx = k + i - 1
        if idx <= N
            wind_pred[i] = scen.forecast[idx]
        else
            # near end of timeseries: repeat last forecast
            wind_pred[i] = scen.forecast[end]
        end
    end

    return wind_pred
end

##########################################################
# MAIN WRAPPER
##########################################################

"""
    make_wind_scenario(Power_base; kwargs...)

Convenience wrapper that:
  1. Interprets `Power_base` as your forecast series.
  2. Computes `P_rated = maximum(Power_base)` unless specified.
  3. Calls `build_scenario`.
  4. Returns both the scenario and `forecast_window`.
"""
function make_wind_scenario(Power_base::Vector{Float64};
    P_rated::Float64 = maximum(Power_base),
    σ::Float64 = 0.05 * P_rated,
    ρ::Float64 = 0.95,
    Δt_minutes::Int = 5,
    rng::AbstractRNG = Random.GLOBAL_RNG,
)

    scen = build_scenario(Power_base;
        P_rated = P_rated,
        σ = σ,
        ρ = ρ,
        Δt_minutes = Δt_minutes,
        rng = rng,
    )

    return scen, forecast_window
end
