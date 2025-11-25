# function Case_29_Model(min_power::Float64, ElCap::Float64, Power::Vector{<:Float64},
#                        age::String="BOL", z1_SB_init::Vector{<:Int}=0, z2_SB_init::Vector{<:Int}=0, 
#                        z1_on_init::Vector{<:Int}=0, z2_on_init::Vector{<:Int}=0,
#                        P_s1_init::Vector{<:Float64}=0.0, P_s2_init::Vector{<:Float64}=0.0,
#                        soh1_init::Float64=100.0, soh2_init::Float64=100.0)
function Case_29_Model(
    min_power::Float64,
    ElCap::Float64,
    Power::Vector{<:Float64},
    age::String = "BOL",
    z1_SB_init::Vector{<:Int} = 0,
    z2_SB_init::Vector{<:Int} = 0,
    z1_on_init::Vector{<:Int} = 0,
    z2_on_init::Vector{<:Int} = 0,
    P_s1_init::Vector{<:Float64} = 0.0,
    P_s2_init::Vector{<:Float64} = 0.0,
    # component-specific SoH values 
    soh1_cold_init::Float64 = 3000.0,
    soh2_cold_init::Float64 = 3000.0,
    soh1_hot_init::Float64 = 3000.0,
    soh2_hot_init::Float64 = 3000.0,
    soh1_run_init::Float64 = 90000.0,
    soh2_run_init::Float64 = 90000.0,
    soh1_fluct_init::Float64 = 90000.0,
    soh2_fluct_init::Float64 = 90000.0;
    weights = (w1=1.0, w2=1.0, w3=0.25, w4=0.25, w5=0.25, w6=0.25)
)


    history =length(z1_SB_init)
    region_bounds = Float64[]
    a = Float64[]; b = Float64[]
    NT = length(Power)

    if age == "BOL"
        region_bounds = [min_power, 0.40*ElCap, ElCap]
        a = [3.7926375000460189, 3.3287446985093916]
        b = [5.5330899893211338, 24.0888042054934992]

    elseif age == "MOL"
        region_bounds = [min_power, 0.86*ElCap, ElCap]
        a = [2.9619427968907002, 2.6728623569246022]
        b = [9.4385795555864860, 34.2994939148910873]

    elseif age == "EOL"
        region_bounds = [min_power, 0.65*ElCap, ElCap]
        a = [2.6042621777507091, 2.3594135896738972]
        b = [2.5664957286021286, 18.5336735363388847]

    else
        error("age must be \"BOL\", \"MOL\", or \"EOL\"")
    end


    @assert length(region_bounds) == 3
    @assert length(a) == 2 && length(b) == 2

    x_knots = region_bounds
    pct = (Power)->(100.0*Power/ElCap) # pct takes Power as input and calulates it as % of ElCap
    # y at knots: take the *upper envelope* at the middle knot to reflect choosing the better region
    y1 = (a[1]*pct(x_knots[1]) + b[1]) / 12.0
    y2_left  = (a[1]*pct(x_knots[2]) + b[1]) / 12.0
    y2_right = (a[2]*pct(x_knots[2]) + b[2]) / 12.0
    y3 = (a[2]*pct(x_knots[3]) + b[2]) / 12.0
    y_knots = [y1, max(y2_left, y2_right), y3]

# === MODEL === Case 24
model = Model(Gurobi.Optimizer)

# === state binaries ===
@variable(model, z1_on[t=1:NT], Bin)
@variable(model, z1_SB[t=1:NT], Bin)
@variable(model, z2_on[t=1:NT], Bin)
@variable(model, z2_SB[t=1:NT], Bin)

# === Constraints for OFF/SB/ON status ===
@constraint(model, [t=1:NT], z1_on[t] + z1_SB[t] <= 1)
@constraint(model, [t=1:NT], z2_on[t] + z2_SB[t] <= 1)
# OFF expressions
@expression(model, z1_OFF[t=1:NT], 1 - z1_on[t] - z1_SB[t])
@expression(model, z2_OFF[t=1:NT], 1 - z2_on[t] - z2_SB[t])

# Disallow OFF → SB and SB → OFF
for t in 2:NT
    @constraint(model, z1_SB[t] <= 1 - z1_OFF[t-1]) # Disallow OFF → SB:
    @constraint(model, z2_SB[t] <= 1 - z2_OFF[t-1])
    @constraint(model, z1_OFF[t] <= 1 - z1_SB[t-1]) # Disallow SB → OFF:
    @constraint(model, z2_OFF[t] <= 1 - z2_SB[t-1])
end

# Prevent any stretch of more than 11 consecutive SB states for each stack (Max 55min SB)
for t in 12:NT
    @constraint(model, sum(z1_SB[i] for i in (t - 12 + 1):t) <= 11)
    @constraint(model, sum(z2_SB[i] for i in (t - 12 + 1):t) <= 11)
end
# # Prevent more than 11 consecutive SB steps across both stacks
# for t in 12:NT
#     @constraint(model, sum(z1_SB[i] + z2_SB[i] for i in (t - 12 + 1):t) <= 11)
# end


    # === PWL hydrogen with SOS2 (no region binaries) ===
    K = length(x_knots)
    @variable(model, λ1[1:NT, 1:K] >= 0)   # convex weights for stack 1
    @variable(model, λ2[1:NT, 1:K] >= 0)   # convex weights for stack 2
    # Each time: either OFF (sum λ = 0) or ON (sum λ = 1). Tie to z_on.
    @constraint(model, [t=1:NT], sum(λ1[t, k] for k in 1:K) == z1_on[t])
    @constraint(model, [t=1:NT], sum(λ2[t, k] for k in 1:K) == z2_on[t])
    # SOS2 adjacency (use x_knots as weights to fix the order)
    @constraint(model, [t=1:NT], λ1[t, :] in MOI.SOS2(x_knots))
    @constraint(model, [t=1:NT], λ2[t, :] in MOI.SOS2(x_knots))

    # Power (kW) and H2 (per 5-min) as affine expressions of λ
    @expression(model, P_s1[t=1:NT], sum(λ1[t, k] * x_knots[k] for k in 1:K))
    @expression(model, P_s2[t=1:NT], sum(λ2[t, k] * x_knots[k] for k in 1:K))
    @expression(model, H2_s1[t=1:NT], sum(λ1[t, k] * y_knots[k] for k in 1:K))
    @expression(model, H2_s2[t=1:NT], sum(λ2[t, k] * y_knots[k] for k in 1:K))

    # Initial power conditions:
    for t in 1:history
    @constraint(model, sum(λ1[t, k] * x_knots[k] for k in 1:K) == P_s1_init[t])
    @constraint(model, sum(λ2[t, k] * x_knots[k] for k in 1:K) == P_s2_init[t])
    end


    # # === Precedence & symmetry-breaking (no both_on + big-M needed) ===
    # @constraint(model, [t=1:NT], z2_on[t] <= z1_on[t])         # stack 2 only if stack 1 ON
    # @constraint(model, [t=1:NT], z2_on[t] => { P_s1[t] >= ElCap })
    # @constraint(model, [t=1:NT], P_s1[t] >= P_s2[t])           # symmetry-breaking

    # === Pruning & implied bound: max # of ON stacks per period ===
    # Fix OFF when Power[t] < min_power
    for t in 1:NT
        if Power[t] < min_power
            fix(z1_on[t], 0; force=true); 
            fix(z2_on[t], 0; force=true); 
        end
    end
    # At most floor(Power/min_power) stacks can be ON
    cap_on = [min(2, Int(floor(Power[t] / min_power))) for t in 1:NT]
    @constraint(model, [t=1:NT], z1_on[t] + z2_on[t] <= cap_on[t])

@constraint(model, z1_SB[1:history]==z1_SB_init)
@constraint(model, z2_SB[1:history]==z2_SB_init)

@constraint(model, z1_on[1:history]==z1_on_init)
@constraint(model, z2_on[1:history]==z2_on_init)

# === POWER LIMIT ===
@constraint(model, [t=1:NT], P_s1[t] + P_s2[t] <= Power[t])

# === STACK OPERATION ===
@constraint(model, [t=1:NT], P_s1[t] >= min_power * z1_on[t])
@constraint(model, [t=1:NT], P_s2[t] >= min_power * z2_on[t])

@constraint(model, [t=1:NT], P_s1[t] <= ElCap * z1_on[t])
@constraint(model, [t=1:NT], P_s2[t] <= ElCap * z2_on[t])

# Enforce OFF→ON only after 12 time steps OFF
@variable(model, z1_cold_start[2:NT], Bin)
@variable(model, z2_cold_start[2:NT], Bin)
# Count cold starts OFF → ON
for t in 2:NT
    @constraint(model, z1_cold_start[t] <= 1- z1_SB[t-1])
    @constraint(model, z1_cold_start[t] <= z1_on[t])
    @constraint(model, z1_cold_start[t] <= 1 - z1_on[t-1])
    @constraint(model, z1_cold_start[t] >= z1_on[t] - z1_SB[t-1] - z1_on[t-1])

    @constraint(model, z2_cold_start[t] <= z2_on[t])
    @constraint(model, z2_cold_start[t] <= 1 - z2_SB[t-1])
    @constraint(model, z2_cold_start[t] <= 1 - z2_on[t-1])
    @constraint(model, z2_cold_start[t] >= z2_on[t] - z2_SB[t-1] - z2_on[t-1])
end

# minimum OFF time of 1 hour (only one cold start per hour)
for t in 13:NT # Normal case: enforce min 12 consecutive OFFs for t >= 13
    @constraint(model, 12.0*z1_cold_start[t] <= sum(z1_OFF[t - 12 : t - 1]))
    @constraint(model, 12.0*z2_cold_start[t] <= sum(z2_OFF[t - 12 : t- 1]))
end

# Startup rule for the first 12 timesteps
for t in 2:12
    @constraint(model, 12.0 * z1_cold_start[t] <= sum(z1_OFF[1:t-1]) + (12 - (t-1)))
    @constraint(model, 12.0 * z2_cold_start[t] <= sum(z2_OFF[1:t-1]) + (12 - (t-1)))
end

# Count hot starts SB → ON
@variable(model, z1_hot_start[2:NT], Bin)
@variable(model, z2_hot_start[2:NT], Bin)

for t in 2:NT
    @constraint(model, z1_hot_start[t] <= z1_SB[t-1])
    @constraint(model, z1_hot_start[t] <= z1_on[t])
    @constraint(model, z1_hot_start[t] >= z1_SB[t-1] + z1_on[t] - 1)

    @constraint(model, z2_hot_start[t] <= z2_SB[t-1])
    @constraint(model, z2_hot_start[t] <= z2_on[t])
    @constraint(model, z2_hot_start[t] >= z2_SB[t-1] + z2_on[t] - 1)
end

" NOTE on abs_delta_P variables:
# - Current formulation with <= constraints only enforces
#       abs_delta_P[t] >= |P[t] - P[t-1]|
#   If abs_delta_P is not in the objective, the solver may leave it larger than
#   the true difference.
#
# Options:
# 1) Exact equality (abs_delta_P[t] = |ΔP| at all times):
#       Requires extra binary direction variables with a Big-M formulation.
#       Guarantees correctness but increases MILP complexity.
#
# 2) Tiny-penalty trick (lighter and faster):
#       Add a very small weight in the objective, e.g.
#           - 1e-6 * sum(abs_delta_P_s1) - 1e-6 * sum(abs_delta_P_s2)
#       This drives the solver to keep abs_delta_P tight to |ΔP| without adding binaries."


# # Calculate power delta in each time step
# @variable(model, abs_delta_P_s1[2:NT] >= 0)
# @variable(model, abs_delta_P_s2[2:NT] >= 0)

# for t in 2:NT
#     @constraint(model,  (P_s1[t] - P_s1[t-1]) <= abs_delta_P_s1[t])
#     @constraint(model, -(P_s1[t] - P_s1[t-1]) <= abs_delta_P_s1[t])

#     @constraint(model,  (P_s2[t] - P_s2[t-1]) <= abs_delta_P_s2[t])
#     @constraint(model, -(P_s2[t] - P_s2[t-1]) <= abs_delta_P_s2[t])
# end

# Signed difference variable
@variable(model, delta_P_s1[2:NT])
@variable(model, delta_P_s2[2:NT])

# Absolute difference variable
@variable(model, abs_delta_P_s1[2:NT] >= 0)
@variable(model, abs_delta_P_s2[2:NT] >= 0)

# Binary direction variables
@variable(model, dir_s1[2:NT], Bin)
@variable(model, dir_s2[2:NT], Bin)

# Link delta to actual power difference
@constraint(model, [t=2:NT], delta_P_s1[t] == P_s1[t] - P_s1[t-1])
@constraint(model, [t=2:NT], delta_P_s2[t] == P_s2[t] - P_s2[t-1])

# Big-M constant (should cover full range of possible differences)
M = 2 * ElCap   # safe since max change between two steps is between -ElCap and ElCap

# Absolute value constraints for stack 1
@constraint(model, [t=2:NT], abs_delta_P_s1[t] >=  delta_P_s1[t])
@constraint(model, [t=2:NT], abs_delta_P_s1[t] >= -delta_P_s1[t])
@constraint(model, [t=2:NT], abs_delta_P_s1[t] <=  delta_P_s1[t] + M * dir_s1[t])
@constraint(model, [t=2:NT], abs_delta_P_s1[t] <= -delta_P_s1[t] + M * (1 - dir_s1[t]))

# Absolute value constraints for stack 2
@constraint(model, [t=2:NT], abs_delta_P_s2[t] >=  delta_P_s2[t])
@constraint(model, [t=2:NT], abs_delta_P_s2[t] >= -delta_P_s2[t])
@constraint(model, [t=2:NT], abs_delta_P_s2[t] <=  delta_P_s2[t] + M * dir_s2[t])
@constraint(model, [t=2:NT], abs_delta_P_s2[t] <= -delta_P_s2[t] + M * (1 - dir_s2[t]))


# SOH 
# End-of-day SoH variables
# @variable(model, soh1 <= 100)
# @variable(model, soh2 <= 100)

# # Degradation weights
# cold_cost = 1/3000    # per cold start
# hot_cost  = 1/30000     # per hot start
# run_cost  = 1/(12*30000)        # per timestep at nominal load
# power_delta_cost = (0.1 * hot_cost) / ElCap

# Degradation weights
cold_cost = 1   # per cold start
hot_cost  = 1    # per hot start
run_cost  = 1      # per timestep at nominal load
power_delta_cost = 1


# Aggregate degradation for stack 1
@expression(model, cold_start_deg1, sum(z1_cold_start[t] for t in 2:NT))
@expression(model, hot_start_deg1,  sum(z1_hot_start[t]  for t in 2:NT))
# @expression(model, power_delta_deg1,sum(abs_delta_P_s1[t] for t in 2:NT)/ElCap)
# @expression(model, run_deg1,        sum(P_s1[t]          for t in 2:NT)/ElCap)
@expression(model, power_delta_deg1,sum(abs_delta_P_s1[t]/(ElCap) for t in 2:NT))
@expression(model, run_deg1,        sum(P_s1[t]/(ElCap*12)          for t in 2:NT))

# Aggregate degradation for stack 2
@expression(model, cold_start_deg2, sum(z2_cold_start[t] for t in 2:NT))
@expression(model, hot_start_deg2,  sum(z2_hot_start[t]  for t in 2:NT))
# @expression(model, power_delta_deg2,sum(abs_delta_P_s2[t] for t in 2:NT)/ElCap)
# @expression(model, run_deg2,        sum(P_s2[t]          for t in 2:NT)/ElCap)
@expression(model, power_delta_deg2,sum(abs_delta_P_s2[t]/(ElCap) for t in 2:NT)) # 1 = full capacity swing
@expression(model, run_deg2,        sum(P_s2[t]/(ElCap*12)      for t in 2:NT)) # 1/12 = 5 min at full capacity

# Transition equations (end-of-day soh)
# @expression(model, soh1, soh1_init
#     - cold_cost * cold_start_deg1
#     - hot_cost  * hot_start_deg1
#     - run_cost  * run_deg1
#     - power_delta_cost *power_delta_deg1
#     )

# @expression(model, soh2, soh2_init
#     - cold_cost * cold_start_deg2
#     - hot_cost  * hot_start_deg2
#     - run_cost  * run_deg2
#     - power_delta_cost *power_delta_deg2
#     )

# Cold-start degradation
@expression(model, soh1_cold, soh1_cold_init - cold_cost * cold_start_deg1)
@expression(model, soh2_cold, soh2_cold_init - cold_cost * cold_start_deg2)

# Hot-start degradation
@expression(model, soh1_hot, soh1_hot_init - hot_cost * hot_start_deg1)
@expression(model, soh2_hot, soh2_hot_init - hot_cost * hot_start_deg2)

# Runtime degradation
@expression(model, soh1_run, soh1_run_init - run_cost * run_deg1)
@expression(model, soh2_run, soh2_run_init - run_cost * run_deg2)

# Fluctuation (ΔP) degradation
@expression(model, soh1_fluct, soh1_fluct_init - power_delta_cost * power_delta_deg1)
@expression(model, soh2_fluct, soh2_fluct_init - power_delta_cost * power_delta_deg2)

# # Cold-start degradation (% of initial life left)
# @expression(model, soh1_cold,  100 - 100 * (cold_cost * cold_start_deg1 / soh1_cold_init))
# @expression(model, soh2_cold,  100 - 100 * (cold_cost * cold_start_deg2 / soh2_cold_init))

# # Hot-start degradation (%)
# @expression(model, soh1_hot,   100 - 100 * (hot_cost * hot_start_deg1 / soh1_hot_init))
# @expression(model, soh2_hot,   100 - 100 * (hot_cost * hot_start_deg2 / soh2_hot_init))

# # Runtime degradation (%)
# @expression(model, soh1_run,   100 - 100 * (run_cost * run_deg1 / soh1_run_init))
# @expression(model, soh2_run,   100 - 100 * (run_cost * run_deg2 / soh2_run_init))

# # Fluctuation degradation (%)
# @expression(model, soh1_fluct, 100 - 100 * (power_delta_cost * power_delta_deg1 / soh1_fluct_init))
# @expression(model, soh2_fluct, 100 - 100 * (power_delta_cost * power_delta_deg2 / soh2_fluct_init))


    

"# NOTE: SOH is only meaningful if it appears in the objective 
# (then SOH = min(soh1, soh2)). 
# If SOH is not part of the objective, remove it entirely to avoid slack."
# @variable( model, SOH )
# @constraint(model, SOH <= soh1)
# @constraint(model, SOH <= soh2)

# === Component-wise SOH variables (worst per degradation type) ===
@variable(model, SOH_cold)
@constraint(model, SOH_cold <= soh1_cold)
@constraint(model, SOH_cold <= soh2_cold)

@variable(model, SOH_hot)
@constraint(model, SOH_hot <= soh1_hot)
@constraint(model, SOH_hot <= soh2_hot)

@variable(model, SOH_run)
@constraint(model, SOH_run <= soh1_run)
@constraint(model, SOH_run <= soh2_run)

@variable(model, SOH_fluct)
@constraint(model, SOH_fluct <= soh1_fluct)
@constraint(model, SOH_fluct <= soh2_fluct)

# === Objective: Maximize Hydrogen Production ===
@objective(model, Max,
    weights.w1 * sum(H2_s1[t] + H2_s2[t] for t in 1:NT) +
    weights.w2 * (weights.w3*SOH_cold 
                    + weights.w4*SOH_hot 
                    + weights.w5*SOH_run 
                    + weights.w6*SOH_fluct)
)


# === SOLVE ===
set_optimizer_attribute(model, "OutputFlag", 0);   # 1 = print log, 0 = silent
set_optimizer_attribute(model, "NodefileDir", "C:\\Lisas_Temp\\"); # pick a fast disk (SSD/local scratch)
set_optimizer_attribute(model, "MemLimit", 258.0);  # GB
set_optimizer_attribute(model, "Threads", 4);  # or 1 if really tight on RAM # increase threads 
#set_optimizer_attribute(model, "Method", 2);    # 0=primal simplex, 1=dual simplex, 2=barrier not working with MILP
set_optimizer_attribute(model, "Crossover", 0); # saves memory (no crossover) not working with MILP
set_optimizer_attribute(model, "MIPFocus", 1);        # find feasible fast
set_optimizer_attribute(model, "Presolve", 2);
#set_optimizer_attribute(model, "Heuristics", 0.3); #comment that out and let Gurobi decide it
set_optimizer_attribute(model, "Cuts", 2);
#set_optimizer_attribute(model, "Symmetry", 2); # comment that out
set_optimizer_attribute(model, "NodefileStart", 1.0); # spill B&B tree to disk after ~1 GB
set_optimizer_attribute(model, "MIPGap", 1e-3)

return model, P_s1, P_s2, H2_s1, H2_s2, z1_OFF, z2_OFF, soh1_cold, soh2_cold,
          soh1_hot,  soh2_hot,
          soh1_run,  soh2_run,
          soh1_fluct, soh2_fluct

end
