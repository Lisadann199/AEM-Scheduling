###############################################################
#                   IMPORTS & SETUP
###############################################################
using JuMP, Gurobi
using CSV, DataFrames
using Plots
using LaTeXStrings
using Dates

include("plot_functions.jl")
include("winddata.jl")
include("model_V3.jl")
include("helper_functions.jl")
include("send_enapter_commands.jl")

ElCap = 2.4 #kW
Power_base = scale_to_range(df_aus.BLUFF1, (2/3)*ElCap);

include("windprofile_module_V2.jl")

# RNG for reproducibility
rng = MersenneTwister(1234)

# Scenario (fixed RNG)
P_rated = maximum(Power_base)
scenario = build_scenario(Power_base; P_rated=P_rated, rng = rng)

###############################################################
#                   MPC CONSTANTS
###############################################################

NT = 288  # horizon
const MPC_PERIOD = Minute(5)  # 5 minute clock
MAX_ITER = 48      # 4 hours at 5 min per iteration
iter_count = 0

# weights
w1 = 1.0
w2 = 100.0
inner_scenarios = [(0.9, 0.005, 0.005)]
w3, w4, w5 = inner_scenarios[1]
weights = (w1=w1, w2=w2, w3=w3, w4=w4, w5=w5)

# warmstart persists across MPC iterations
warmstart = Dict{String, Vector{Float64}}()

# storage of results
all_results = Dict{Int, Dict}()

###############################################################
#               SINGLE MPC ITERATION FUNCTION
###############################################################

function run_mpc_step(k)
    println("------------------------------------------------")
    println("Running MPC step for k = $k at time $(now())")
    println("------------------------------------------------")
    global warmstart  
    ################################################################
    #                 READ MEASUREMENTS
    ################################################################
    status_stack_1_342A, timestamp = read_measurement(STACKS["342A"],"status",READING_TOKEN)
    status_stack_2_A568,  _        = read_measurement(STACKS["A568"],"status",READING_TOKEN)
    status_stack_3_AD7F,  _        = read_measurement(STACKS["AD7F"],"status",READING_TOKEN)

    z1_on_init = status_stack_1_342A == "steady" ? 1 : 0
    z2_on_init = status_stack_2_A568 == "steady" ? 1 : 0
    z3_on_init = status_stack_3_AD7F == "steady" ? 1 : 0

    # handle unknown states
    if !(status_stack_1_342A in ("steady","idle"))
        println("ERROR: Unknown stack status: $status_stack_1_342A")
    end
    if !(status_stack_2_A568 in ("steady","idle"))
        println("ERROR: Unknown stack status: $status_stack_2_A568")
    end
    if !(status_stack_3_AD7F in ("steady","idle"))
        println("ERROR: Unknown stack status: $status_stack_3_AD7F")
    end

    err1, _ = read_measurement(STACKS["342A"],"errors_exists",READING_TOKEN)
    err2, _ = read_measurement(STACKS["A568"],"errors_exists",READING_TOKEN)
    err3, _ = (true, nothing) # TEMPORARY: error measurement disabled

    ################################################################
    #                     POWER READINGS
    ################################################################
    stack_1_voltage, _ = read_measurement(STACKS["342A"],"PSU_in_v",READING_TOKEN)
    stack_1_current, _ = read_measurement(STACKS["342A"],"HASS_in_a",READING_TOKEN)
    #P_s1_init = round(stack_1_voltage * stack_1_current / 1000; digits=2)

    stack_2_voltage, _ = read_measurement(STACKS["A568"],"PSU_in_v",READING_TOKEN)
    stack_2_current, _ = read_measurement(STACKS["A568"],"HASS_in_a",READING_TOKEN)
    #P_s2_init = round(stack_2_voltage * stack_2_current / 1000; digits=2)

    stack_3_voltage, _ = read_measurement(STACKS["AD7F"],"PSU_in_v",READING_TOKEN)
    stack_3_current, _ = read_measurement(STACKS["AD7F"],"HASS_in_a",READING_TOKEN)
    #P_s3_init = round(stack_3_voltage * stack_3_current / 1000; digits=2)

    ################################################################
    #                  PRODUCTION RATES
    ################################################################
    production_rate_s1_342A, _ = read_measurement(STACKS["342A"],"production_rate",READING_TOKEN)
    production_rate_s2_A568, _ = read_measurement(STACKS["A568"],"production_rate",READING_TOKEN)
    production_rate_s3_AD7F, _ = read_measurement(STACKS["AD7F"],"production_rate",READING_TOKEN)

    setpoint_s1_init = float(z1_on_init) * production_rate_s1_342A
    setpoint_s2_init = float(z2_on_init) * production_rate_s2_A568
    setpoint_s3_init = float(z3_on_init) * production_rate_s3_AD7F

    ################################################################
    #                   SOH METRICS
    ################################################################
    stack_cycles_s1_342A, _ = read_measurement(STACKS["342A"],"stack_cycles",READING_TOKEN)
    stack_cycles_s2_A568, _ = read_measurement(STACKS["A568"],"stack_cycles",READING_TOKEN)
    stack_cycles_s3_AD7F, _ = read_measurement(STACKS["AD7F"],"stack_cycles",READING_TOKEN)

    soh1_ramping_init = 1000.0 - stack_cycles_s1_342A
    soh2_ramping_init = 1000.0 - stack_cycles_s2_A568
    soh3_ramping_init = 1000.0 - stack_cycles_s3_AD7F

    h2_total_s1_342A, _ = read_measurement(STACKS["342A"],"h2_total",READING_TOKEN)
    h2_total_s2_A568, _ = read_measurement(STACKS["A568"],"h2_total",READING_TOKEN)
    h2_total_s3_AD7F, _ = read_measurement(STACKS["AD7F"],"h2_total",READING_TOKEN)

    soh1_run_init   = 9000.0 - h2_total_s1_342A / 500.0
    soh2_run_init   = 9000.0 - h2_total_s2_A568 / 500.0
    soh3_run_init   = 9000.0 - h2_total_s3_AD7F / 500.0

    soh1_fluct_init = 9000.0
    soh2_fluct_init = 9000.0
    soh3_fluct_init = 9000.0

    ################################################################
    #                   DIAGNOSTICS STORAGE
    ################################################################
    measured = Dict(
        "status_stack_1_342A" => status_stack_1_342A,
        "status_stack_2_A568" => status_stack_2_A568,
        "status_stack_3_AD7F" => status_stack_3_AD7F,
        "err1" => err1,
        "err2" => err2,
        "err3" => err3,
        "stack_1_voltage" => stack_1_voltage,
        "stack_1_current" => stack_1_current,
        "stack_2_voltage" => stack_2_voltage,
        "stack_2_current" => stack_2_current,
        "stack_3_voltage" => stack_3_voltage,
        "stack_3_current" => stack_3_current,
        "production_rate_s1_342A" => production_rate_s1_342A,
        "production_rate_s2_A568" => production_rate_s2_A568,
        "production_rate_s3_AD7F" => production_rate_s3_AD7F,
        "stack_cycles_s1_342A" => stack_cycles_s1_342A,
        "stack_cycles_s2_A568" => stack_cycles_s2_A568,
        "stack_cycles_s3_AD7F" => stack_cycles_s3_AD7F,
        "h2_total_s1_342A" => h2_total_s1_342A,
        "h2_total_s2_A568" => h2_total_s2_A568,
        "h2_total_s3_AD7F" => h2_total_s3_AD7F
    )

    ################################################################
    #                FORECAST WINDOW FOR THIS STEP
    ################################################################
    Power_wind = forecast_window(scenario, k, NT)

    ################################################################
    #                      BUILD THE MODEL
    ################################################################
    model, P_s1, P_s2, P_s3, H2_s1, H2_s2, H2_s3,
        z1_OFF, z2_OFF, z3_OFF,
        soh1_ramping, soh2_ramping, soh3_ramping,
        soh1_run, soh2_run, soh3_run,
        soh1_fluct, soh2_fluct, soh3_fluct =
            Model_V3(ElCap, Power_wind,
                err1, err2, err3,
                z1_on_init, z2_on_init, z3_on_init,
                setpoint_s1_init, setpoint_s2_init, setpoint_s3_init,
                soh1_ramping_init, soh2_ramping_init, soh3_ramping_init,
                soh1_run_init, soh2_run_init, soh3_run_init,
                soh1_fluct_init, soh2_fluct_init, soh3_fluct_init;
                weights = weights)

    ################################################################
    #                     WARM START IF AVAILABLE
    ################################################################
    if !isempty(warmstart)
        for v in all_variables(model)
            nm = name(v)
            if haskey(warmstart, nm)
                set_start_value(v, warmstart[nm])
            end
        end
    end

    ################################################################
    #                OPTIMIZE
    ################################################################
    optimize!(model)
    status = termination_status(model)
    println("Solver termination: $status")

    if status != MOI.OPTIMAL
        println(">>> Optimization failed at k = $k")
        return
    end

    ################################################################
    #           EXTRACT SOLUTION + SAVE WARM START
    ################################################################
    vars = JuMP.name.(JuMP.all_variables(model))
    vals = JuMP.value.(JuMP.all_variables(model)); 

    # update warmstart for next iteration
    empty!(warmstart)
    warmstart = Dict(vars[j] => vals[j] for j in eachindex(vars))

    # Convert to dict
    dict2 = Dict(vars[i] => vals[i] for i in eachindex(vars))
    dict3 = group_dict(dict2)

    dict3["z1_OFF"] = value.(z1_OFF)
    dict3["z2_OFF"] = value.(z2_OFF)
    dict3["z3_OFF"] = value.(z3_OFF)

    dict3["H2_s1"] = value.(H2_s1[2:NT])
    dict3["H2_s2"] = value.(H2_s2[2:NT])
    dict3["H2_s3"] = value.(H2_s3[2:NT])

    # Remove the init elements
    for key in keys(dict3)
        if key in ["soh1_ramping","soh2_ramping","soh3_ramping","SOH_ramping",
                   "soh1_run","soh2_run","soh3_run","SOH_run",
                   "soh1_fluct","soh2_fluct","soh3_fluct","SOH_fluct",
                   "H2_s1","H2_s2","H2_s3"]
            continue
        end
        dict3[key] = dict3[key][2:end]
    end

    ################################################################
    #                  DETERMINE FIRST CONTROL MOVE
    ################################################################

    setpoint_s1 = dict3["z1_on"][2] * dict3["setpoint_s1"][2]
    setpoint_s2 = dict3["z2_on"][2] * dict3["setpoint_s2"][2]

    z1_on = Int(dict3["z1_on"][2])
    z2_on = Int(dict3["z2_on"][2])

    println("Setpoint 342A: $setpoint_s1")
    println("Setpoint A568: $setpoint_s2")

    ################################################################
    #                    SEND COMMANDS
    ################################################################
    action_taken = false

    #### STACK 1 ####
    if z1_on_init == 1 && z1_on == 1
        if 60 <= setpoint_s1 <= 100
            send_command("342A", "set_production_rate", setpoint_s1)
            println("set production rate stack 342A $setpoint_s1")
            action_taken = true
        end
    elseif z1_on_init == 1 && z1_on == 0
        send_command("342A", "stop")
        println("stopped stack 342A")
        action_taken = true
    elseif z1_on_init == 0 && z1_on == 1
        if 60 <= setpoint_s1 <= 100
            send_command("342A", "start")
            println("started stack 342A")
            send_command("342A", "set_production_rate", setpoint_s1)
            println("set production rate stack 342A $setpoint_s1")
            action_taken = true
        end
    end

    #### STACK 2 ####
    if z2_on_init == 1 && z2_on == 1
        if 60 <= setpoint_s2 <= 100
            send_command("A568", "set_production_rate", setpoint_s2)
            println("set production rate stack A568 $setpoint_s2")
            action_taken = true
        end
    elseif z2_on_init == 1 && z2_on == 0
        send_command("A568", "stop")
        println("stopped stack A568")
        action_taken = true
    elseif z2_on_init == 0 && z2_on == 1
        if 60 <= setpoint_s2 <= 100
            send_command("A568", "start")
            println("started stack A568")
            send_command("A568", "set_production_rate", setpoint_s2)
            println("set production rate stack A568 $setpoint_s2")
            action_taken = true
        end
    end

    if !action_taken
        println("NOTHING HAPPENED")
    end

    ################################################################
    #                STORE RESULTS
    ################################################################
    all_results[k] = Dict(
        "measured" => measured,
        "model_outputs" => deepcopy(dict3),
        "z1_on_init" => z1_on_init,
        "z2_on_init" => z2_on_init,
        "z3_on_init" => z3_on_init,
        "timestamp" => timestamp,
        "status" => status,
    )

    println("Finished MPC step for k=$k at $(now())")

end  # end function run_mpc_step


###############################################################
#                  MPC CLOCK LOOP (5-MINUTE CYCLE)
###############################################################

k = 42  # initial scenario index
next_run = now()  # run immediately

println("===== STARTING 5-MINUTE MPC CLOCK AT $(now()) =====")

while iter_count < MAX_ITER
    iter_start = now()
    println(" MPC iteration started at $iter_start")

    try
        run_mpc_step(k)
    catch e
        println(" ERROR: MPC failed at iteration $(iter_count+1).")
        println("   Reason: $e")
        println("   Stopping the 4-hour run at $(now()).")
        break   # <---- STOP EVERYTHING
    end

    k += 1  # advance horizon index

    iter_end = now()
    println(" MPC iteration completed at $iter_end")
    println(" Iteration duration: $(iter_end - iter_start)\n")

    # schedule next run
    next_run += MPC_PERIOD
    sleep_time = next_run - now()

    println(" Heartbeat:")
    println("      Next MPC run at: $next_run")
    println("      Sleep time:      $sleep_time")
    println("--------------------------------------------------")

    if sleep_time > Second(0)
        sleep(Dates.value(sleep_time)/1000)  # convert ms → s
    else
        println("⚠ WARNING: MPC overran by $(-sleep_time)")
        # you may optionally do:
        # next_run = now()
    end
    iter_count += 1
    println(" Completed $iter_count / $MAX_ITER iterations")

end


rows = Vector{NamedTuple}()

for k in sort(collect(keys(all_results)))
    entry = all_results[k]
    timestamp = entry["timestamp"]

    measured = entry["measured"]
    model    = entry["model_outputs"]

    ### -------------------------------------------
    ### 1) STORE MEASURED VALUES
    ### -------------------------------------------
    for (mvar, mval) in measured
        # measured signals are scalar → t = 1
        push!(rows, (
            k = k,
            timestamp = timestamp,
            source = "measured",
            varname = mvar,
            t = 1,
            value = mval,
        ))
    end

    ### -------------------------------------------
    ### 2) STORE INIT states (z1_on_init, etc.)
    ### -------------------------------------------
    for initname in ["z1_on_init", "z2_on_init", "z3_on_init"]
        push!(rows, (
            k = k,
            timestamp = timestamp,
            source = "measured_init",
            varname = initname,
            t = 1,
            value = entry[initname],
        ))
    end

    ### -------------------------------------------
    ### 3) STORE MODEL OUTPUTS
    ### -------------------------------------------
    for (var, values) in model
        if isa(values, AbstractVector)
            # horizon-dependent vector (t = 1..NT)
            for (t, v) in enumerate(values)
                push!(rows, (
                    k = k,
                    timestamp = timestamp,
                    source = "model",
                    varname = var,
                    t = t,
                    value = v,
                ))
            end
        else
            # scalar model output (SOH values, etc.)
            push!(rows, (
                k = k,
                timestamp = timestamp,
                source = "model",
                varname = var,
                t = 1,
                value = values,
            ))
        end
    end

end

df = DataFrame(rows)
CSV.write("mpc_results_4hour_test_0112.csv", df)

println("Saved mpc_results_long_with_measured.csv")
println("===== MPC FINISHED OR STOPPED EARLY AT $(now()) =====")

###############################
#  SAFE STACK SHUTDOWN
###############################
println("Shutting down all stacks...")

for stack in ["342A", "A568"]#, "AD7F"]
    try
        send_command(stack, "stop")
        println("Stopped stack $stack")
    catch e
        @warn "Failed to stop stack $stack: $e"
    end
end

println("All stacks stopped. Test completed.")



# df_H2_now = filter(row -> row.source == "model" &&
#                               row.t == 1 &&
#                               occursin("H2_s", row.varname), df)

# plt = plot()

# for var in ["H2_s1", "H2_s2", "H2_s3"]
#     dfv = filter(:varname => ==(var), df_H2_now)
#     plot!(plt, dfv.k, dfv.value, label=var, lw=2)
# end

# xlabel!("MPC iteration k")
# ylabel!("H₂ flow at t=1 (NL/h)")
# title!("H₂ production applied at each MPC step")
# display(plt)
