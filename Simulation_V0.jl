using JuMP, Gurobi
using LaTeXStrings
using Printf
using Plots
using CSV, DataFrames

pgfplotsx()
include("group_dict.jl")
include("winddata.jl")
include("plot_functions.jl")
include("model_V1.jl")

ElCap = 2.4 #kW
Power_base = scale_to_range(df_day.BLUFF1, ElCap);
start_idx = 181
end_idx = start_idx+72
plot(Power_base[start_idx:end_idx])
hline!([0.6*2.4], color=:black, linestyle=:dash, label="2.4")
hline!([2.4], color=:red, linestyle=:dash, label="2.4")
hline!([2 * 2.4], color=:red, linestyle=:dash, label="4.8")
hline!([3 * 2.4], color=:red, linestyle=:dash, label="7.2")

# DAYS = 7;
# date_vector = df.ts
# start_date = Date(2024,05,03)
# start_day_index = findfirst(d -> Date(d) == start_date && Time(d) == Time(0), date_vector)
# end_day_index = start_day_index + DAYS * 288 - 1

init_time = 12
init_power = zeros(init_time)
Power_wind = [init_power; Power_base[start_idx:end_idx]]
NT = length(Power_wind)
# inital values
z1_on_init = zeros(Int, init_time)
z2_on_init = zeros(Int, init_time)
z3_on_init = zeros(Int, init_time)

P_s1_init = zeros(init_time)
P_s2_init = zeros(init_time)
P_s3_init = zeros(init_time)

setpoint_s1_init = zeros(init_time)
setpoint_s2_init = zeros(init_time)
setpoint_s3_init = zeros(init_time)

soh1_ramping_init = 100.0
soh2_ramping_init = 100.0
soh3_ramping_init = 100.0

soh1_run_init = 9000.0
soh2_run_init = 9000.0
soh3_run_init = 9000.0

soh1_fluct_init = 9000.0
soh2_fluct_init = 9000.0
soh3_fluct_init = 9000.0
begin

acc = Dict{String, Vector{Any}}()  
dict3=Dict{String, Vector{Float64}}()
w1 = 1.0
w2 = 100.0
inner_scenarios = [(0.9,0.005,0.005)] #C2
w3, w4, w5 = inner_scenarios[1]

weights = (w1=w1, w2=w2, w3=w3, w4=w4, w5=w5)
warmstart = Dict{String, Vector{Float64}}()# storage for warm start between days



model, P_s1, P_s2, P_s3, H2_s1, H2_s2, H2_s3, z1_OFF, z2_OFF, z3_OFF, soh1_ramping,     soh2_ramping, soh3_ramping,
    soh1_run, soh2_run, soh3_run,
    soh1_fluct, soh2_fluct,soh3_fluct = Model_V1(ElCap,Power_wind,z1_on_init,z2_on_init, z3_on_init,
    P_s1_init,
    P_s2_init,
    P_s3_init,
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

vars = name.(all_variables(model))
vals = value.(all_variables(model)); 
dict2 = Dict(vars[i] => vals[i] for i in eachindex(vars));
dict3 = group_dict(dict2)
dict3["z1_OFF"] = value.(z1_OFF)
dict3["z2_OFF"] = value.(z2_OFF)
dict3["z3_OFF"] = value.(z3_OFF)
dict3["H2_s1"] = value.(H2_s1[t] for t in length(z1_on_init)+1:NT)
dict3["H2_s2"] = value.(H2_s2[t] for t in length(z1_on_init)+1:NT)
dict3["H2_s3"] = value.(H2_s3[t] for t in length(z1_on_init)+1:NT)

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

dict3["z1_OFF"]
dict3["H2_s3"]
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
end

sum(P_s1_vals)
sum(P_s2_vals)
sum(P_s2_vals)

# Plot result
tick_every = Hour(2)  # tick every 1 hour
tick_idx   = start_idx:floor(Int, tick_every ÷ Minute(5)):end_idx#+1
tick_labels = first.(df_day.Time[tick_idx], 5)
tick_pos = (tick_idx .- start_idx .+1)./12
NT_without_init = NT- length(z1_on_init)

plt1 = heatmap_schedule(z1_on_vals,z2_on_vals,z3_on_vals,z1_OFF_vals,z2_OFF_vals,z3_OFF_vals,NT_without_init,tick_pos,tick_labels)

plt2 = layered_power_plot(P_s1_vals,P_s2_vals, P_s3_vals,ElCap, Power_wind[13:NT], NT_without_init, tick_pos,tick_labels)

plt3 = individual_power_plot(P_s1_vals,P_s2_vals,P_s3_vals,z1_on_vals,z2_on_vals,z3_on_vals,NT_without_init,ElCap,tick_pos,tick_labels)

scatter(acc["setpoint_s3"].*acc["z3_on"])
scatter!(acc["setpoint_s3"])

setpoint_stack1  = acc["setpoint_s1"].*acc["z1_on"]
setpoint_stack2  = acc["setpoint_s2"].*acc["z2_on"]
setpoint_stack3  = acc["setpoint_s3"].*acc["z3_on"]

plot(setpoint_S1)
plot!(setpoint_S2)
plot!(setpoint_S3)



delta_time = 300  # 5 min in seconds

df = DataFrame(
    "commands" => String[],
    "argument" => Float64[],
    "duration" => Int[],
    "342A" => Int[],
    "A568" => Int[],
    "AD7F" => Int[]
)


prev = [setpoint_stack1[1], setpoint_stack2[1], setpoint_stack3[1]]
accum = 0   # accumulated time since last command

# send initial commands
changes = [(1, prev[1]), (2, prev[2]), (3, prev[3])]

for (k,(idx,val)) in enumerate(changes)
    duration = (k == length(changes)) ? delta_time : 0
    push!(df, ("set_production_rate", val, duration,
               idx == 1 ? 1 : 0,
               idx == 2 ? 1 : 0,
               idx == 3 ? 1 : 0))
end

accum = 0

for i in 2:length(setpoint_stack1)
    curr = [setpoint_stack1[i], setpoint_stack2[i], setpoint_stack3[i]]

    # accumulate time
    accum += delta_time

    # detect changes
    changes = [(j, curr[j]) for j in 1:3 if curr[j] != prev[j]]

    if !isempty(changes)
        for (k,(idx,val)) in enumerate(changes)
            duration = (k == length(changes)) ? accum : 0
            push!(df, ("set_production_rate", val, duration,
                       idx == 1 ? 1 : 0,
                       idx == 2 ? 1 : 0,
                       idx == 3 ? 1 : 0))
        end
        accum = 0  # reset after sending
    end

    prev = curr
end

allowmissing!(df, :argument)
push!(df, ("stop",missing ,300,1,1,1))

CSV.write("output.csv", df)

using CSV, DataFrames
using CSV, DataFrames

function build_schedule(s1, s2, s3; timestep=300.0)

    stacks = [s1, s2, s3]
    n = length(s1)

    df = DataFrame(
        commands = String[],
        argument = String[],
        duration = Float64[],
        STACK1 = Int[],
        STACK2 = Int[],
        STACK3 = Int[]
    )

    prev = [0.0, 0.0, 0.0]
    idle_steps = 0

    # helper: add accumulated wait to previous row
    function add_wait_to_previous()
        if idle_steps > 0
            if nrow(df) > 0
                df.duration[end] += idle_steps * timestep
            else
                # no previous row → create a wait row
                push!(df, ("", "", idle_steps * timestep, 0, 0, 0))
            end
        end
        idle_steps = 0
        return idle_steps
    end

    for i in 1:n
        current = [stacks[j][i] for j in 1:3]
        commands_this_step = []

        for (j, val) in enumerate(current)
            was = prev[j]

            if was == 0 && val > 0
                idle_steps = add_wait_to_previous()
                push!(commands_this_step, ("start", "", j))
                push!(commands_this_step, ("set_production_rate", string(val), j))

            elseif was > 0 && val == 0
                idle_steps = add_wait_to_previous()
                push!(commands_this_step, ("stop", "", j))

            elseif was > 0 && val != was
                idle_steps = add_wait_to_previous()
                push!(commands_this_step, ("set_production_rate", string(val), j))
            end
        end

        if !isempty(commands_this_step)
            for idx in 1:length(commands_this_step)
                cmd, arg, j = commands_this_step[idx]
                dur = (idx == length(commands_this_step)) ? timestep : 0.0
                push!(df, (cmd, arg, dur, j==1, j==2, j==3))
            end
        else
            idle_steps += 1
        end

        prev .= current
    end

    # Add any final waiting time
    add_wait_to_previous()

    return df
end


# Usage:
setpoint_stack1 = round.(acc["setpoint_s1"] .* acc["z1_on"], digits=2)
setpoint_stack2 = round.(acc["setpoint_s2"] .* acc["z2_on"], digits=2)
setpoint_stack3 = round.(acc["setpoint_s3"] .* acc["z3_on"], digits=2)

schedule = build_schedule(setpoint_stack1, setpoint_stack2, setpoint_stack3; timestep=300.0)
CSV.write("electrolyzer_schedule.csv", schedule)

df_setpoints = DataFrame(
    setpoint_stack1 = setpoint_stack1,
    setpoint_stack2 = setpoint_stack2,
    setpoint_stack3 = setpoint_stack3
)
