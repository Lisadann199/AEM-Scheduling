using JuMP, Gurobi
using Plots
using Random
using LaTeXStrings
using CSV, Dates
using StatsBase
using DataFrames
using DataFrames: groupby
using IterTools

pgfplotsx()
include("Winddata.jl");
include("group_dict.jl")
include("plot_functions.jl")
include("Case_29_Model.jl")

DAYS = 3;
date_vector = df.ts
start_date = Date(2024,03,05)
start_day_index = findfirst(d -> Date(d) == start_date && Time(d) == Time(0), date_vector)
end_day_index = start_day_index + DAYS * 288 - 1

#ElCap = 2.135e6 # in W
ElCap = 100.0; # Scaled to % #### 17.55e6; # in W
P = 25; # system pressure
#begin
# Power_base = scale_to_range(df_day.BLUFF1, ElCap);
Power_base = scale_to_range(one_year_wind, ElCap); # Data loaded in "Winddata.jl"
# Power_base = scale_to_range(df_day.BLUFF1,ElCap)
# Power_base = repeat(Power_base, DAYS) ; # Length will now be 288 * DAYS
#Power_base =80*(ones(289))
#plot(Power_base[start_day_index:end_day_index+288])

min_power = [];
age = [];
all_dfs = DataFrame[]  # will hold results for each age
# === Outer weights ===
w1 = 1.0
w2_values = [0.0,1.0,10.0,100.0,500.0,1000.0,1250.0,1500.0,1520.0,1530.0]#,1540.0,1550.0,1560.0]
w2_values = [1.0, 10.0,100.0]
w2_values = [10.0]
# === Inner grid ===
inner_scenarios = [(0.900,0.090,0.005,0.005)] #C2
inner_scenarios = [
#     (0.25,0.25,0.25,0.25), # base case
#     # Extreme cases
#     (1.0, 0.0, 0.0, 0.0),
#     (0.0, 1.0, 0.0, 0.0),
#     (0.0, 0.0, 1.0, 0.0),
#     (0.0, 0.0, 0.0, 1.0),
#     # # Single-emphasis cases
#     (0.4, 0.2, 0.2, 0.2),
#     (0.2, 0.4, 0.2, 0.2),
#     (0.2, 0.2, 0.4, 0.2),
#     (0.2, 0.2, 0.2, 0.4),
#     # Dual-emphasis cases
#     (0.333, 0.333, 0.167, 0.167),
#     (0.333, 0.167, 0.333, 0.167),
#     (0.333, 0.167, 0.167, 0.333),
#     (0.167, 0.333, 0.333, 0.167),
#     (0.167, 0.333, 0.167, 0.333),
#     (0.167, 0.167, 0.333, 0.333),
#     # Triple-emphasis cases 
#     (0.143, 0.286, 0.286, 0.286), # T1
#     (0.286, 0.143, 0.286, 0.286), # T2
#     (0.286, 0.286, 0.143, 0.286), # T3
#     (0.286, 0.286, 0.286, 0.143), # T4
#     # Extreme weighting (10× cold start emphasis)
#     (0.769, 0.077, 0.077, 0.077),  # X1
    (0.2807, 0.6273, 0.0076, 0.0849) # based on the results of the base case and then weights normalized
]

for w2 in w2_values, (w3,w4,w5,w6) in inner_scenarios
#for (w3,w4,w5,w6) in inner_scenarios

weights = (w1=w1, w2=w2, w3=w3, w4=w4, w5=w5, w6=w6)
println(">>> Running w1=$w1, w2=$w2, w3=$w3, w4=$w4, w5=$w5, w6=$w6")

#for a in 1:3 #["BOL", "MOL", "EOL"];
a=1
    # === AGE-DEPENDENT PARAMETERS ===
    if a == 1 
        age ="BOL"
        min_power = (-0.576 + 1.365 * P)# Calculate minimum power required for a stack to be on in 1-100%
    elseif a == 2 
        age = "MOL"
        min_power = (-0.2998+ 1.654 *P) 
    elseif a == 3 
        age ="EOL"
        min_power = (0.007 + 1.938 * P)
    end

    # === INITIAL CONDITIONS ===
    Power_init = [0]
    z1_SB_init = [0]
    z2_SB_init = [0]
    z1_on_init = [0]
    z2_on_init = [0]
    P_s1_init = [0.0]
    P_s2_init = [0.0]
    soh1_cold_init = 3000.0
    soh2_cold_init = 3000.0
    soh1_hot_init= 3000.0
    soh2_hot_init = 3000.0
    soh1_run_init = 90000.0
    soh2_run_init = 90000.0
    soh1_fluct_init = 90000.0
    soh2_fluct_init = 90000.0

    acc = Dict{String, Vector{Any}}()  
    dict3=Dict{String, Vector{Float64}}()
    warmstart = Dict{String, Vector{Float64}}()# storage for warm start between days

    for i in start_day_index:288:end_day_index 

        day_start = i
        #day_end = i + (i == (end_day_index-287) ? 288 : 288 - 1)
        day_end = i +  288 - 1

        Power = [Power_init; Power_base[day_start:day_end]]

        model, P_s1, P_s2, H2_s1, H2_s2, z1_OFF, z2_OFF,
          soh1_cold, soh2_cold,
          soh1_hot,  soh2_hot,
          soh1_run,  soh2_run,
          soh1_fluct, soh2_fluct = Case_29_Model(
              min_power, ElCap, Power, age,
              z1_SB_init, z2_SB_init, z1_on_init, z2_on_init,
              P_s1_init, P_s2_init,
              soh1_cold_init, soh2_cold_init,
              soh1_hot_init,  soh2_hot_init,
              soh1_run_init,  soh2_run_init,
              soh1_fluct_init, soh2_fluct_init;
              weights=weights
          )

        # === apply warm start if available ===
        if !isempty(warmstart)
            for v in all_variables(model)
                nm = name(v)
                if haskey(warmstart, nm)
                    set_start_value(v, warmstart[nm])
                end
            end
        end

        optimize!(model);
        println(date_vector[i])
        status = termination_status(model);
        #println("[$age] ",status)

        if status != MOI.OPTIMAL # not optimal solution found
            println("Stopped at iteration $i: problem is infeasible or unbounded.")
            println(date_vector[i])
            println(">>> stopped with w1=$w1, w2=$w2, w3=$w3, w4=$w4, w5=$w5, w6=$w6")

            break
        end

        vars = name.(all_variables(model));
        vals = value.(all_variables(model)); 
        dict2 = Dict(vars[i] => vals[i] for i in eachindex(vars));
        dict3 = group_dict(dict2);
        #dict3["SOH"] = [dict2["SOH"]]
        # Add all the expressions that are not variables to the model.
        dict3["Power"]  = Power # add Power as an entry to dict3
        dict3["P_s1"]   = value.(P_s1)
        dict3["P_s2"]   = value.(P_s2)
        dict3["H2_s1"]  = value.(H2_s1)  # wrap scalar in vector so mergewith(vcat, ...) works
        dict3["H2_s2"]  = value.(H2_s2)
        dict3["z1_OFF"] = value.(z1_OFF)
        dict3["z2_OFF"] = value.(z2_OFF)
        dict3["soh1_cold"]  = [value(soh1_cold)]
        dict3["soh2_cold"]  = [value(soh2_cold)]
        dict3["soh1_hot"]   = [value(soh1_hot)]
        dict3["soh2_hot"]   = [value(soh2_hot)]
        dict3["soh1_run"]   = [value(soh1_run)]
        dict3["soh2_run"]   = [value(soh2_run)]
        dict3["soh1_fluct"] = [value(soh1_fluct)]
        dict3["soh2_fluct"] = [value(soh2_fluct)]


        # === prepare warm start for next loop ===
        warmstart = Dict(vars[j] => vals[j] for j in eachindex(vars))

        # slice off init part before saving:
        for key in keys(dict3)
            if key in ["soh1_cold","soh2_cold", "SOH_cold",
                        "soh1_hot","soh2_hot",  "SOH_hot",
                        "soh1_run","soh2_run", "SOH_run",
                        "soh1_fluct","soh2_fluct", "SOH_fluct"]
                continue
            end
            dict3[key] = dict3[key][length(z1_SB_init)+1:end]
        end


        z1_SB_init = round.(Int,dict3["z1_SB"][end-11:end])  # update initial conditions for next iteration
        z2_SB_init = round.(Int,dict3["z2_SB"][end-11:end])
        z1_on_init = round.(Int,dict3["z1_on"][end-11:end])
        z2_on_init = round.(Int,dict3["z2_on"][end-11:end])
        Power_init = Power[end-11:end]
        P_s1_init = Float64.(dict3["P_s1"][end-11:end])
        P_s2_init = Float64.(dict3["P_s2"][end-11:end])
        soh1_cold_init  = dict3["soh1_cold"][1]
        soh2_cold_init  = dict3["soh2_cold"][1]
        soh1_hot_init   = dict3["soh1_hot"][1]
        soh2_hot_init   = dict3["soh2_hot"][1]
        soh1_run_init   = dict3["soh1_run"][1]
        soh2_run_init   = dict3["soh2_run"][1]
        soh1_fluct_init = dict3["soh1_fluct"][1]
        soh2_fluct_init = dict3["soh2_fluct"][1]

        acc = mergewith(vcat, acc, dict3)   # accumulate results      
    end
    # === Attach date column (aligned with start_day_index) ===
    nrows = length(first(values(acc)))
    acc["ts"] = date_vector[start_day_index : start_day_index + nrows - 1]
    for (k, v) in acc
    if length(v) < nrows
        # pad with missing values at the end
        acc[k] = vcat(v, fill(missing, nrows - length(v)))
    elseif length(v) > nrows
        # truncate to the last nrows values
        acc[k] = v[end-nrows+1:end]
    end
end

    # === CONVERT TO DATAFRAME ===
    df_results = DataFrame(acc)
    df_results[!, :age] .= age  # add column for age
    df_results[!, :w1] .= weights.w1
    df_results[!, :w2] .= weights.w2
    df_results[!, :w3] .= weights.w3
    df_results[!, :w4] .= weights.w4
    df_results[!, :w5] .= weights.w5
    df_results[!, :w6] .= weights.w6
    push!(all_dfs, df_results)
end

#### EXTRACT SIMULATION RESULTS #######
# === ONE CSV WITH ALL AGES ===
df_all = vcat(all_dfs...)
Strategy ="Case_29 27 Oct inner weights lost simulations"
CSV.write("C:\\Users\\lisadan\\OneDrive - Danmarks Tekniske Universitet\\12_Research\\06_Control_paper\\03_plots\\04_rolling_horizon\\results_$(start_date)_$(DAYS)_days_$Strategy.csv", df_all)
#end 
z1_on_vals   = round.(Int, acc["z1_on"])
z1_SB_vals   = round.(Int, acc["z1_SB"])
z1_OFF_vals  = round.(Int, acc["z1_OFF"])

z2_on_vals   = round.(Int, acc["z2_on"])
z2_SB_vals   = round.(Int, acc["z2_SB"])
z2_OFF_vals  = round.(Int, acc["z2_OFF"])

P_s1_vals    = acc["P_s1"]
P_s2_vals    = acc["P_s2"]

H2_s1 = Float64.(acc["H2_s1"])*12.0 # H2_s1 is in kg/5min in the model
H2_s2 = Float64.(acc["H2_s2"])*12.0

NT = length(z1_on_vals)
H2_s1_total = sum(value(H2_s1[t])./12.0 for t in 1:NT) # total H2 production in kg
H2_s2_total = sum(value(H2_s2[t])./12.0 for t in 1:NT)

Power_vals   = acc["Power"]         # <-- added your Power series

# === Post-processing ===
z1_on_time = count(==(1), z1_on_vals) / 12
z2_on_time = count(==(1), z2_on_vals) / 12

# Wind curtailment
Power_curtailed = sum((Power_vals[1:NT].-(P_s1_vals.+P_s2_vals))./12)*17.55 # Curtailed wind energy in MWh

## OBJECTIVE TERM VALUES ###

H2_output   =       sum(H2_s1[t] + H2_s2[t] for t in 1:NT)
Hot_starts  =       sum(round.(Int,acc["z1_hot_start"][t]) for t in 2:NT)
Hot_starts2 =       sum(round.(Int,acc["z2_hot_start"][t]) for t in 2:NT)
Cold_starts =       sum(round.(Int,acc["z1_cold_start"][t])  for t in 2:NT)
Cold_starts2 =       sum(round.(Int,acc["z2_cold_start"][t])  for t in 2:NT)
Power_delta =       sum(acc["abs_delta_P_s1"][t] for t in 2:NT)
Power_delta =       sum(acc["abs_delta_P_s2"][t] for t in 2:NT)
total_power = sum(P_s1_vals[t] for t in 1:NT)
total_power2 = sum(P_s2_vals[t] for t in 1:NT)


## PRINT RESULTS ##
println("\n" * "="^50)
println("     RESULTS   S4a   START DATE: $start_date   $DAYS DAYS ")
println("="^50)

println("Age: ", age,"        Number of simulated days: ", DAYS)

println("\nCold Starts     | Hot Starts       | On Time [h]       | H₂ Prod [kg]")
println("-"^50)
println("S1: ", Cold_starts, "   | S1: ", Hot_starts, "   | S1: ", z1_on_time, "   | S1: ", H2_s1_total)
println("S2: ", Cold_starts2, "   | S2: ", Hot_starts2, "   | S2: ", z2_on_time, "   | S2: ", H2_s2_total)

println("\nWind Curtailment [MWh]: ", Power_curtailed)
println("\nMin Power [MW]: ", min_power)
println("="^50)

## Plot result

tick_every = Hour(1*24)  # tick every 12 hours
tick_idx   = start_day_index:floor(Int, tick_every ÷ Minute(5)):end_day_index+1
tick_pos   = (tick_idx .- start_day_index .+ 1) ./ 12 
#tick_labels = Dates.format.(date_vector[tick_idx], "L{dd-u\\\\ HH:MM}")

tick_labels = [raw"\shortstack{" *
               Dates.format(date_vector[i], "dd-u") *
               raw"\\ " *
               Dates.format(date_vector[i], "HH:MM") *
               "}" for i in tick_idx]


plt1 = heatmap_schedule(z1_on_vals,z2_on_vals,z1_SB_vals,z2_SB_vals,z1_OFF_vals,z2_OFF_vals,NT,tick_pos,tick_labels)

plt2 = individual_power_plot(P_s1_vals,P_s2_vals,z1_on_vals,z2_on_vals,NT,ElCap,tick_pos,tick_labels)

plt3 = layered_power_plot(P_s1_vals, P_s2_vals,ElCap,Power_vals,NT, tick_pos, tick_labels)

plt4 = layered_production_plot(H2_s1, H2_s2,NT,tick_pos,tick_labels)

# savefig(plt1, "C:\\Users\\lisadan\\OneDrive - Danmarks Tekniske Universitet\\12_Research\\06_Control_paper\\03_plots\\04_rolling_horizon\\Heatmap_$(start_date)_$(DAYS)_days.pdf")

# savefig(plt3, "C:\\Users\\lisadan\\OneDrive - Danmarks Tekniske Universitet\\12_Research\\06_Control_paper\\03_plots\\04_rolling_horizon\\LayeredPower_$(start_date)_$(DAYS)_days.pdf")

# savefig(plt4, "C:\\Users\\lisadan\\OneDrive - Danmarks Tekniske Universitet\\12_Research\\06_Control_paper\\03_plots\\04_rolling_horizon\\Layered_production_$(start_date)_$(DAYS)_days.pdf")


# ## CHECK IF SOS2 WORKS ##
#     k = 288
#     H2_s1[k]
#     H2_s2[k]
#     P_s1_vals[k]
#     P_s2_vals[k]

#     acc["H2_s1"][k]*12

#     a = [3.7926375000460189, 3.3287446985093916]
#     b = [5.5330899893211338, 24.0888042054934992]
#     m = a[1]*P_s1_vals[k] + b[1]
#     m = a[2]*P_s1_vals[k] + b[2]

#     m = a[1]*P_s2_vals[k] + b[1]
#     m = a[2]*P_s2_vals[k] + b[2]

using Plots

time = 2:NT   # skip t=1 if that's what you intended

# Hot starts
z1_hot  = round.(Int, acc["z1_hot_start"][time])
z2_hot  = round.(Int, acc["z2_hot_start"][time])

# Cold starts
z1_cold = round.(Int, acc["z1_cold_start"][time])
z2_cold = round.(Int, acc["z2_cold_start"][time])

# Power deltas
p1_delta = acc["abs_delta_P_s1"][time]
p2_delta = acc["abs_delta_P_s2"][time]

# Total power
p1_total = P_s1_vals[1:NT]
p2_total = P_s2_vals[1:NT]

# Compute cumulative sums
cumsum_hot1  = cumsum(z1_hot)
cumsum_hot2  = cumsum(z2_hot)
cumsum_cold1 = cumsum(z1_cold)
cumsum_cold2 = cumsum(z2_cold)
cumsum_p1delta = cumsum(p1_delta)
cumsum_p2delta = cumsum(p2_delta)
cumsum_p1total = cumsum(p1_total)
cumsum_p2total = cumsum(p2_total)

# Plot them individually
plot(time, cumsum_hot1, seriestype=:steppost, label="Hot starts 1", title="Hot Starts 1")
plot(time, cumsum_hot2, seriestype=:steppost, label="Hot starts 2", title="Hot Starts 2")
plot(time, cumsum_cold1, seriestype=:steppost, label="Cold starts 1", title="Cold Starts 1")
plot(time, cumsum_cold2, seriestype=:steppost, label="Cold starts 2", title="Cold Starts 2")
plot(time, cumsum_p1delta, label="ΔP s1", title="Power Δ s1")
plot(time, cumsum_p2delta, label="ΔP s2", title="Power Δ s2")
plot(time, cumsum_p1total, label="Power s1", title="Total Power s1")
plot(time, cumsum_p2total, label="Power s2", title="Total Power s2")


inner_scenarios = [
    # Balanced
    # (0.25, 0.25, 0.25, 0.25),

    # === Extreme cases ===
    (1.0, 0.0, 0.0, 0.0),
    (0.0, 1.0, 0.0, 0.0),
    (0.0, 0.0, 1.0, 0.0),
    (0.0, 0.0, 0.0, 1.0),

    # # === Single-dominant (α=5) ===  → (0.625, 0.125, 0.125, 0.125)
    # (0.625, 0.125, 0.125, 0.125),
    # (0.125, 0.625, 0.125, 0.125),
    # (0.125, 0.125, 0.625, 0.125),
    # (0.125, 0.125, 0.125, 0.625),

    # === Single-dominant (α=10) === → (0.769, 0.077, 0.077, 0.077)
    (0.769, 0.077, 0.077, 0.077),
    (0.077, 0.769, 0.077, 0.077),
    (0.077, 0.077, 0.769, 0.077),
    (0.077, 0.077, 0.077, 0.769),

    # # === Dual-dominant (α=5) === → (0.417, 0.417, 0.083, 0.083)
    # (0.417, 0.417, 0.083, 0.083),
    # (0.417, 0.083, 0.417, 0.083),
    # (0.417, 0.083, 0.083, 0.417),
    # (0.083, 0.417, 0.417, 0.083),
    # (0.083, 0.417, 0.083, 0.417),
    # (0.083, 0.083, 0.417, 0.417),

    # === Dual-dominant (α=10) === → (0.455, 0.455, 0.045, 0.045)
    (0.455, 0.455, 0.045, 0.045),
    (0.455, 0.045, 0.455, 0.045),
    (0.455, 0.045, 0.045, 0.455),
    (0.045, 0.455, 0.455, 0.045),
    (0.045, 0.455, 0.045, 0.455),
    (0.045, 0.045, 0.455, 0.455),

    # # === Triple-dominant (α=5) === → (0.313, 0.313, 0.313, 0.063)
    # (0.313, 0.313, 0.313, 0.063),
    # (0.313, 0.313, 0.063, 0.313),
    # (0.313, 0.063, 0.313, 0.313),
    # (0.063, 0.313, 0.313, 0.313),

    # === Triple-dominant (α=10) === → (0.323, 0.323, 0.323, 0.032)
    (0.323, 0.323, 0.323, 0.032),
    (0.323, 0.323, 0.032, 0.323),
    (0.323, 0.032, 0.323, 0.323),
    (0.032, 0.323, 0.323, 0.323)
]


inner_scenarios = [
    # --- Single emphasis (ratio 100:1)
    (0.9709, 0.0097, 0.0097, 0.0097),     # S1c
    (0.0097, 0.9709, 0.0097, 0.0097),     # S2c 
    (0.0097, 0.0097, 0.9709, 0.0097),     # S3c 
    (0.0097, 0.0097, 0.0097, 0.9709),     # S4c 

    # --- Dual emphasis (ratio 100:1)
    (0.4950, 0.4950, 0.0050, 0.0050),     # D1c 
    (0.4950, 0.0050, 0.4950, 0.0050),     # D2c 
    (0.4950, 0.0050, 0.0050, 0.4950),     # D3c 
    (0.0050, 0.4950, 0.4950, 0.0050),     # D4c 
    (0.0050, 0.4950, 0.0050, 0.4950),     # D5c 
    (0.0050, 0.0050, 0.4950, 0.4950),     # D6c 

    # --- Triple emphasis (ratio 100:1)
    (0.3322, 0.3322, 0.3322, 0.0033),     # T1c
    (0.3322, 0.3322, 0.0033, 0.3322),     # T2c
    (0.3322, 0.0033, 0.3322, 0.3322),     # T3c
    (0.0033, 0.3322, 0.3322, 0.3322)      # T4c
]

inner_scenarios = [(0.900,0.090,0.001,0.009)] #C1 
inner_scenarios = [(0.900,0.090,0.005,0.005)] #C2
inner_scenarios = [(0.900,0.090,0.0011,0.0089)] #C3
inner_scenarios = [(0.909,0.091,0.000,0.000)] #C3
