using Random, Distributions


"""
    struct WindScenario

Holds wind forecast and actual (truth) on the same time grid.
"""
struct WindScenario
    forecast::Vector{Float64}
    actual::Vector{Float64}
    Δt_minutes::Int
end

"""
    build_scenario(wind_forecast; P_rated, σ, ρ)

Create an actual wind profile by adding correlated noise to the forecast.
- wind_forecast: vector of forecasted wind power
- P_rated: maximum wind power
- σ: std of forecast error (in power units)
- ρ: correlation of forecast error between consecutive steps (0–1)
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
    err = zeros(Float64, N)
    noise = Normal(0.0, σ * sqrt(1 - ρ^2))

    # AR(1) forecast error
    err[1] = rand(rng, Normal(0, σ))
    for k in 2:N
        err[k] = ρ * err[k-1] + rand(rng, noise)
    end

    wind_actual = similar(wind_forecast)
    @inbounds for k in 1:N
        wind_actual[k] = clamp(wind_forecast[k] + err[k], 0.0, P_rated)
    end

    return WindScenario(wind_forecast, wind_actual, Δt_minutes)
end

"""
    forecast_window(scen, k, N_h)

Get the forecast window for MPC step k with horizon N_h.
This is what you feed into JuMP at time step k.
"""
function forecast_window(scen::WindScenario, k::Int, N_h::Int)
    N = length(scen.forecast)
    k_end = min(k + N_h - 1, N)
    return view(scen.forecast, k:k_end)
end

Δt_minutes = 5
# Suppose you have some forecast series already:
wind_forecast = Power_base  # Vector{Float64}, one value per 5 min

P_rated = maximum(wind_forecast)  # or your turbine rating
scenario = build_scenario(wind_forecast; P_rated=P_rated)
wind_pred =[]
# main simulation / MPC loop
for k in 1:length(wind_forecast)
    # 1) "true" wind power that the plant sees
    P_wind = scenario.actual[k]

    # 2) forecast window for MPC (disturbance prediction)
    wind_pred = forecast_window(scenario, k, 72)  # vector

    # 3) update MPC model with this disturbance forecast
    #    (for example as a parameter in JuMP)
    # set_value.(mpc.wind_param[1:length(wind_pred)], wind_pred)

    # 4) solve MPC, apply first control move, simulate plant with P_wind
    # optimize!(mpc.model)
    # u = value.(mpc.u[1])
    # simulate_plant!(x, u, P_wind)

    # 5) advance 5 minutes (your simulation time index is k)
end

wind_pred

using Plots
using .WindProfile   # assuming your module is in the same file or included

# --- 1) Create a 400-step forecast (example data) ---
N = 400
Power_base = abs.(randn(N) .* 150 .+ 500)   # mean 500, std 150

# --- 2) Build scenario (forecast + real wind) ---
P_rated = maximum(Power_base)              # or set to turbine rating
rng = MersenneTwister(1234)     # fixed RNG
scenario = build_scenario(Power_base; P_rated=P_rated, rng=rng)

# --- 3) Extract series ---
forecast = scenario.forecast
realwind = scenario.actual

# --- 4) Plot ---
plot(forecast[1:400],
     label = "Forecast",
     xlabel = "Time Step (5 min each)",
     ylabel = "Power",
     title = "Wind Forecast vs Real Wind")

plot!(realwind[1:400],
      label = "Real Wind")

