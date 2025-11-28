using JuMP, Gurobi
using CSV, DataFrames
using Plots
using LaTeXStrings
include("plot_functions.jl")
include("winddata.jl")
include("model_V2.jl")
include("helper_functions.jl")
include("send_enapter_commands.jl")
ElCap = 2.4 #kW
Power_base = scale_to_range(df_aus.BLUFF1, ElCap);

include("windprofile_module_V2.jl")

# 1) Fixed RNG for reproducibility
rng = MersenneTwister(1234)

# 2) Build scenario with fixed RNG
P_rated = maximum(Power_base)
scenario = build_scenario(Power_base; P_rated=P_rated, rng=rng)

# 3) Plot the first 400 values
# Nplot = min(400, length(scenario.forecast))
# k = 25
# p1 = plot(
#     k:Nplot,
#     scenario.forecast[k:Nplot],
#     label = "Forecast",
#     lw = 2,
#     xlabel = "Time step",
#     ylabel = "Power",
#     title = "Wind Forecast vs Actual (First 400 samples)",
# )

# plot!(
#     k:Nplot,
#     scenario.actual[k:Nplot],
#     label = "Actual",
#     lw = 2,
# )

for k in 25:27

status_stack_1_342A, timestamp = read_measurement(STACKS["342A"],"status",READING_TOKEN)

if status_stack_1_342A == "steady"
    z1_on_init = [1]
else
    z1_on_init = [0]
end

status_stack_2_A568, timestamp = read_measurement(STACKS["A568"],"status",READING_TOKEN)

if status_stack_2_A568 == "steady"
    z2_on_init = [1]
else
    z2_on_init = [0]
end

status_stack_3_AD7F, timestamp = read_measurement(STACKS["AD7F"],"status",READING_TOKEN)

if status_stack_3_AD7F == "steady"
    z3_on_init = [1]
else
    z3_on_init = [0]
end

err1, _ = read_measurement(STACKS["342A"],"errors_exists",READING_TOKEN)
err2, _ = read_measurement(STACKS["A568"],"errors_exists",READING_TOKEN)
err3, _ = (true, nothing) #read_measurement(STACKS["AD7F"],"errors_exists",READING_TOKEN)

stack_1_voltage, _ = read_measurement(STACKS["342A"],"PSU_in_v",READING_TOKEN)
stack_1_current, _ = read_measurement(STACKS["342A"],"HASS_in_a",READING_TOKEN)

P_s1_init = [stack_1_voltage*stack_1_current/1000]

stack_2_voltage, _ = read_measurement(STACKS["A568"],"PSU_in_v",READING_TOKEN)
stack_2_current, _ = read_measurement(STACKS["A568"],"HASS_in_a",READING_TOKEN)

P_s2_init = round.([stack_2_voltage*stack_2_current/1000],digits=1)

stack_3_voltage, _ = read_measurement(STACKS["AD7F"],"PSU_in_v",READING_TOKEN)
stack_3_current, _ = read_measurement(STACKS["AD7F"],"HASS_in_a",READING_TOKEN)
P_s3_init = round.([stack_3_voltage*stack_3_current/1000],digits=1)

production_rate_s1_342A, _ = read_measurement(STACKS["342A"],"production_rate",READING_TOKEN)
setpoint_s1_init = float(z1_on_init*production_rate_s1_342A)

production_rate_s2_A568, _ = read_measurement(STACKS["A568"],"production_rate",READING_TOKEN)
setpoint_s2_init = float(z2_on_init*production_rate_s2_A568)

production_rate_s3_AD7F, _ = read_measurement(STACKS["AD7F"],"production_rate",READING_TOKEN)
setpoint_s3_init = float(z3_on_init*production_rate_s3_AD7F)

stack_cycles_s1_342A, _ = read_measurement(STACKS["342A"],"stack_cycles",READING_TOKEN)
stack_cycles_s2_A568, _ = read_measurement(STACKS["A568"],"stack_cycles",READING_TOKEN)
stack_cycles_s3_AD7F, _ = read_measurement(STACKS["AD7F"],"stack_cycles",READING_TOKEN)

soh1_ramping_init = 1000.0 - stack_cycles_s1_342A
soh2_ramping_init = 1000.0 - stack_cycles_s2_A568
soh3_ramping_init = 1000.0 - stack_cycles_s3_AD7F

h2_total_s1_342A, _ = read_measurement(STACKS["342A"],"h2_total",READING_TOKEN)
h2_total_s2_A568, _ = read_measurement(STACKS["A568"],"h2_total",READING_TOKEN)
h2_total_s3_AD7F, _ = read_measurement(STACKS["AD7F"],"h2_total",READING_TOKEN)

soh1_run_init = 9000.0 - h2_total_s1_342A/500.0
soh2_run_init = 9000.0 - h2_total_s2_A568/500.0
soh3_run_init = 9000.0 -h2_total_s3_AD7F/500.0

# previous fluctuations could not be measured, therefore this is the same init value for every optimization horizon
soh1_fluct_init = 9000.0
soh2_fluct_init = 9000.0
soh3_fluct_init = 9000.0



NT = 72
Power_wind = forecast_window(scenario, k, NT)

acc = Dict{String, Vector{Any}}()  
dict3=Dict{String, Vector{Float64}}()
w1 = 1.0
w2 = 100.0
inner_scenarios = [(0.9,0.005,0.005)] #C2
w3, w4, w5 = inner_scenarios[1]

weights = (w1=w1, w2=w2, w3=w3, w4=w4, w5=w5)
warmstart = Dict{String, Vector{Float64}}()# storage for warm start between days

model, P_s1, P_s2, P_s3, H2_s1, H2_s2, H2_s3, z1_OFF, z2_OFF, z3_OFF, soh1_ramping, soh2_ramping, soh3_ramping,
    soh1_run, soh2_run, soh3_run,
    soh1_fluct, soh2_fluct,soh3_fluct = Model_V2(ElCap,Power_wind,
    err1, err2, err3, 
    z1_on_init,z2_on_init, z3_on_init,
    P_s1_init,
    P_s2_init,
    P_s3_init,
    setpoint_s1_init,
    setpoint_s2_init,
    setpoint_s3_init,
    soh1_ramping_init,
    soh2_ramping_init,
    soh3_ramping_init,
    soh1_run_init,
    soh2_run_init,
    soh3_run_init,
    soh1_fluct_init,
    soh2_fluct_init,
    soh3_fluct_init,
    weights =weights )
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
status = termination_status(model);
println(status)
# if status != MOI.OPTIMAL # not optimal solution found
#     println("Stopped at iteration $i: problem is infeasible or unbounded.")
#     println(date_vector[i])
#     println(">>> stopped with w1=$w1, w2=$w2, w3=$w3, w4=$w4, w5=$w5, w6=$w6")

#     break
# end

vars = JuMP.name.(JuMP.all_variables(model))
vals = JuMP.value.(JuMP.all_variables(model)); 
dict2 = Dict(vars[i] => vals[i] for i in eachindex(vars));
dict3 = group_dict(dict2)
dict3["z1_OFF"] = JuMP.value.(z1_OFF)
dict3["z2_OFF"] = JuMP.value.(z2_OFF)
dict3["z3_OFF"] = JuMP.value.(z3_OFF)
dict3["H2_s1"] = JuMP.value.(H2_s1[t] for t in length(z1_on_init)+1:NT)
dict3["H2_s2"] = JuMP.value.(H2_s2[t] for t in length(z1_on_init)+1:NT)
dict3["H2_s3"] = JuMP.value.(H2_s3[t] for t in length(z1_on_init)+1:NT)

# === prepare warm start for next loop ===
warmstart = Dict(vars[j] => vals[j] for j in eachindex(vars))

        # slice off init part before saving:
for key in keys(dict3)
    if key in ["soh1_ramping","soh2_ramping", "soh3_ramping", "SOH_ramping",
                "soh1_run","soh2_run", "SOH_run",
                "soh1_fluct","soh2_fluct", "SOH_fluct", "H2_s1","H2_s2","H2_s3"]
        continue
    end
    dict3[key] = dict3[key][length(z1_on_init)+1:end]
end

acc = mergewith(vcat, acc, dict3)   # accumulate results  

z1_on_vals   = round.(Int, acc["z1_on"])
z1_SB_vals   = round.(Int,zeros(size(z1_on_vals)))
z1_OFF_vals  = round.(Int, acc["z1_OFF"])

z2_on_vals   = round.(Int, acc["z2_on"])
z2_SB_vals   = round.(Int,zeros(size(z1_on_vals)))
z2_OFF_vals  = round.(Int, acc["z2_OFF"])

z3_on_vals   = round.(Int, acc["z3_on"])
z3_SB_vals   = round.(Int,zeros(size(z1_on_vals)))
z3_OFF_vals  = round.(Int, acc["z3_OFF"])

P_s1_vals    = acc["P_s1"]
P_s2_vals    = acc["P_s2"]
P_s3_vals    = acc["P_s3"]


H2_s1 = Float64.(acc["H2_s1"])# H2_s1 is in NL/h in the model
H2_s2 = Float64.(acc["H2_s2"])
H2_s3 = Float64.(acc["H2_s3"])

sum_rampings_s1 = sum(round.(Int, acc["z1_ramping"][2:end]))
sum_rampings_s2 = sum(round.(Int, acc["z2_ramping"][2:end]))
sum_rampings_s3 = sum(round.(Int, acc["z3_ramping"][2:end]))
total_rampings = sum_rampings_s1 + sum_rampings_s2 + sum_rampings_s3
#end
# Plot result
# start_idx = 1
# end_idx =length(P_s1_vals)-1
# tick_every = Hour(2)  # tick every 1 hour
# tick_idx   = start_idx:floor(Int, tick_every ÷ Minute(5)):end_idx#+1
# tick_labels = first.(df_day.Time[tick_idx], 5)
# tick_pos = (tick_idx .- start_idx .+1)./12
# NT_without_init = NT- length(z1_on_init)

# plt1 = heatmap_schedule(z1_on_vals,z2_on_vals,z3_on_vals,z1_OFF_vals,z2_OFF_vals,z3_OFF_vals,NT_without_init,tick_pos,tick_labels)

# plt2 = layered_power_plot(P_s1_vals,P_s2_vals, P_s3_vals,ElCap, Power_wind[1:end-1], NT_without_init, tick_pos,tick_labels)

# Power_wind
# plt3 = individual_power_plot(P_s1_vals,P_s2_vals,P_s3_vals,z1_on_vals,z2_on_vals,z3_on_vals,NT_without_init,ElCap,tick_pos,tick_labels)
# display(plt3)

# send_command("342A","set_production_rate",79.5)
# send_command("342A","stop")

setpoint_s1 = acc["z1_on"][1]*acc["setpoint_s1"][1]
setpoint_s2 = acc["z2_on"][1]*acc["setpoint_s2"][1]

z1_on = acc["z1_on"][1]
z2_on = acc["z2_on"][1]
println("Setpoint 342A: $setpoint_s1")
println("Setpoint A568: $setpoint_s2")


if z1_on_init == 1 && z1_on == 1
    if setpoint_s1 >= 60 && setpoint_s1 <= 100
        send_command("342A", "set_production_rate", setpoint_s1)
    end

elseif z1_on_init == 1 && z1_on == 0
    send_command("342A", "stop")

elseif z1_on_init == 0 && z1_on == 1
    if setpoint_s1 >= 60 && setpoint_s1 <= 100
        send_command("342A", "start")
        send_command("342A", "set_production_rate", setpoint_s1)
    end
end


if z2_on_init == 1 && z2_on == 1
    if setpoint_s2 >= 60 && setpoint_s2 <= 100
        send_command("A568", "set_production_rate", setpoint_s2)
    end

elseif z2_on_init == 1 && z2_on == 0
    send_command("A568", "stop")

elseif z2_on_init == 0 && z2_on == 1
    if setpoint_s2 >= 60 && setpoint_s2 <= 100
        send_command("A568", "start")
        send_command("A568", "set_production_rate", setpoint_s2)
    end
end

    println("Waiting 5 minutes...")
    sleep(5*60 )   # pause 5 minutes

end


