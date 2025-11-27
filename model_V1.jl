# the code to generate a milp model with operating constraints for the AEM Electrolyzer (3 stacks)
function Model_V1(
    ElCap::Float64,
    Power::Vector{<:Float64},
    z1_on_init::Vector{<:Int} = 0,
    z2_on_init::Vector{<:Int} = 0,
    z3_on_init::Vector{<:Int} = 0,
    P_s1_init::Vector{<:Float64} = 0.0,
    P_s2_init::Vector{<:Float64} = 0.0,
    P_s3_init::Vector{<:Float64} = 0.0,
    # component-specific SoH values 
    soh1_ramping_init::Float64 = 100.0,
    soh2_ramping_init::Float64 = 100.0,
    soh3_ramping_init::Float64 = 100.0,
    soh1_run_init::Float64 = 9000.0,
    soh2_run_init::Float64 = 9000.0,
    soh3_run_init::Float64 = 9000.0,
    soh1_fluct_init::Float64 = 90000.0,
    soh2_fluct_init::Float64 = 90000.0,
    soh3_fluct_init::Float64 = 90000.0;
    weights = (w1=1.0, w2=1.0, w3=0.25, w4=0.25, w5=0.25)
)

NT = length(Power)
history =length(z1_on_init)

# === MODEL === 
model = Model(Gurobi.Optimizer)

# === state binaries ===
@variable(model, z1_on[t=1:NT], Bin)
@variable(model, z2_on[t=1:NT], Bin)
@variable(model, z3_on[t=1:NT], Bin)

@constraint(model, z1_on[1:history]==z1_on_init)
@constraint(model, z2_on[1:history]==z2_on_init)
@constraint(model, z3_on[1:history]==z3_on_init)

@expression(model, z1_OFF[t=1:NT], 1 - z1_on[t])
@expression(model, z2_OFF[t=1:NT], 1 - z2_on[t])
@expression(model, z3_OFF[t=1:NT], 1 - z3_on[t])

# === power ===
@variable(model, 0 <= P_s1[t=1:NT] <= ElCap)
@variable(model, 0 <= P_s2[t=1:NT] <= ElCap)
@variable(model, 0 <= P_s3[t=1:NT] <= ElCap)

# Initial power conditions:
@constraint(model,[t=1:history], P_s1[t] == P_s1_init[t])
@constraint(model,[t=1:history], P_s2[t] == P_s2_init[t])
@constraint(model,[t=1:history], P_s3[t] == P_s3_init[t])

# === Power balance constraint ===
@constraint(model, [t=1:NT], P_s1[t] + P_s2[t] + P_s3[t] <= Power[t])

# === Setpoints ===
@variable(model, 0 <= setpoint_s1[t=1:NT] <= 100)   # in percent (60–100)
@variable(model, 0 <=setpoint_s2[t=1:NT] <= 100)
@variable(model, 0 <=setpoint_s3[t=1:NT]<= 100)

@constraint(model, setpoint_s1[1:history] == setpoint_s1_init)
@constraint(model, setpoint_s2[1:history] == setpoint_s2_init)
@constraint(model, setpoint_s3[1:history] == setpoint_s3_init)

# for t in 1:NT
#     @constraint(model, setpoint_s1[t] >= 60 * z1_on[t])
#     @constraint(model, setpoint_s1[t] <= 100 * z1_on[t])

#     @constraint(model, setpoint_s2[t] >= 60 * z2_on[t])
#     @constraint(model, setpoint_s2[t] <= 100 * z2_on[t])

#     @constraint(model, setpoint_s3[t] >= 60 * z3_on[t])
#     @constraint(model, setpoint_s3[t] <= 100 * z3_on[t])
# end

# === linear fit for power consumption curve ===
a = 0.0250818060738514
b = -0.1901347621495934
min_power = (a * 60+ b)
# === STACK LOGIC ===
@constraint(model, [t=1:NT], P_s1[t] >= min_power* z1_on[t])
@constraint(model, [t=1:NT], P_s2[t] >= min_power* z2_on[t])
@constraint(model, [t=1:NT], P_s3[t] >= min_power* z3_on[t])

@constraint(model, [t=1:NT], P_s1[t] <= ElCap * z1_on[t])
@constraint(model, [t=1:NT], P_s2[t] <= ElCap * z2_on[t])
@constraint(model, [t=1:NT], P_s3[t] <= ElCap * z3_on[t])

@constraint(model, [t=history+1:NT], P_s1[t] == (a * setpoint_s1[t] + b))
@constraint(model, [t=history+1:NT], P_s2[t] == (a * setpoint_s2[t] + b))
@constraint(model, [t=history+1:NT], P_s3[t] == (a * setpoint_s3[t] + b))

H_coeff = 5.0   # NL/h per percentage point
@expression(model, H2_s1[t=history+1:NT] , H_coeff*setpoint_s1[t] )
@expression(model, H2_s2[t=history+1:NT] , H_coeff*setpoint_s2[t] )
@expression(model, H2_s3[t=history+1:NT] , H_coeff*setpoint_s3[t] )

# Rampings 
# Count rampings OFF → ON
@variable(model, z1_ramping[2:NT], Bin)
@variable(model, z2_ramping[2:NT], Bin)
@variable(model, z3_ramping[2:NT], Bin)

for t in 2:NT
    @constraint(model, z1_ramping[t] <= z1_OFF[t-1])
    @constraint(model, z1_ramping[t] <= z1_on[t])
    @constraint(model, z1_ramping[t] >= z1_OFF[t-1] + z1_on[t] - 1)

    @constraint(model, z2_ramping[t] <= z2_OFF[t-1])
    @constraint(model, z2_ramping[t] <= z2_on[t])
    @constraint(model, z2_ramping[t] >= z2_OFF[t-1] + z2_on[t] - 1)

    @constraint(model, z3_ramping[t] <= z3_OFF[t-1])
    @constraint(model, z3_ramping[t] <= z3_on[t])
    @constraint(model, z3_ramping[t] >= z3_OFF[t-1] + z3_on[t] - 1)
end

# Max 1 ramping in any 1-hour window (sliding)
window = 12   # 12×5 minutes = 1 hour
for t in window+1:NT
    @constraint(model, sum(z1_ramping[τ] for τ in t-window+1:t) <= 1)
    @constraint(model, sum(z2_ramping[τ] for τ in t-window+1:t) <= 1)
    @constraint(model, sum(z3_ramping[τ] for τ in t-window+1:t) <= 1)
end

# # Moving window (if you use MPC later on)
# L = 288
# for t in history+1:NT
#     τ_start = max(2, t-L+1)
#     @constraint(model, sum(z1_ramping[τ] for τ in τ_start:t) <= 5)
#     @constraint(model, sum(z2_ramping[τ] for τ in τ_start:t) <= 5)
#     @constraint(model, sum(z3_ramping[τ] for τ in τ_start:t) <= 5)
# end

# Scaled
max_starts = 5 #floor(Int, 5 * NT / 288)
@constraint(model, sum(z1_ramping[t] for t in 2:NT) <= max_starts)
@constraint(model, sum(z2_ramping[t] for t in 2:NT) <= max_starts)
@constraint(model, sum(z3_ramping[t] for t in 2:NT) <= max_starts)

# Signed difference variable
@variable(model, delta_P_s1[2:NT])
@variable(model, delta_P_s2[2:NT])
@variable(model, delta_P_s3[2:NT])

# Absolute difference variable
@variable(model, abs_delta_P_s1[2:NT] >= 0)
@variable(model, abs_delta_P_s2[2:NT] >= 0)
@variable(model, abs_delta_P_s3[2:NT] >= 0)

# Binary direction variables
@variable(model, dir_s1[2:NT], Bin)
@variable(model, dir_s2[2:NT], Bin)
@variable(model, dir_s3[2:NT], Bin)

# Link delta to actual power difference
@constraint(model, [t=2:NT], delta_P_s1[t] == P_s1[t] - P_s1[t-1])
@constraint(model, [t=2:NT], delta_P_s2[t] == P_s2[t] - P_s2[t-1])
@constraint(model, [t=2:NT], delta_P_s3[t] == P_s3[t] - P_s3[t-1])

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

# Absolute value constraints for stack 3
@constraint(model, [t=2:NT], abs_delta_P_s3[t] >=  delta_P_s3[t])
@constraint(model, [t=2:NT], abs_delta_P_s3[t] >= -delta_P_s3[t])
@constraint(model, [t=2:NT], abs_delta_P_s3[t] <=  delta_P_s3[t] + M * dir_s3[t])
@constraint(model, [t=2:NT], abs_delta_P_s3[t] <= -delta_P_s3[t] + M * (1 - dir_s3[t]))

# SOH
# Aggregate degradation for stack 1
@expression(model, ramping_deg1, sum(z1_ramping[t] for t in 2:NT))
@expression(model, power_delta_deg1,sum(abs_delta_P_s1[t]/(ElCap) for t in 2:NT))
@expression(model, run_deg1,        sum(P_s1[t]/(ElCap*12)          for t in 2:NT))

# Aggregate degradation for stack 2
@expression(model, ramping_deg2,  sum(z2_ramping[t]  for t in 2:NT))
@expression(model, power_delta_deg2, sum(abs_delta_P_s2[t]/(ElCap) for t in 2:NT)) # 1 = full capacity swing
@expression(model, run_deg2,        sum(P_s2[t]/(ElCap*12)      for t in 2:NT)) # 1/12 = 5 min at full capacity

# Aggregate degradation for stack 3
@expression(model, ramping_deg3,  sum(z3_ramping[t]  for t in 2:NT))
@expression(model, power_delta_deg3, sum(abs_delta_P_s3[t]/(ElCap) for t in 2:NT)) # 1 = full capacity swing
@expression(model, run_deg3,        sum(P_s2[t]/(ElCap*12)      for t in 2:NT)) # 1/12 = 5 min at full capacity

# ramping degradation
@expression(model, soh1_ramping, soh1_ramping_init - ramping_deg1)
@expression(model, soh2_ramping, soh2_ramping_init - ramping_deg2)
@expression(model, soh3_ramping, soh3_ramping_init - ramping_deg3)

# Runtime degradation
@expression(model, soh1_run, soh1_run_init - run_deg1)
@expression(model, soh2_run, soh2_run_init - run_deg2)
@expression(model, soh3_run, soh3_run_init - run_deg3)

# Fluctuation (ΔP) degradation
@expression(model, soh1_fluct, soh1_fluct_init - power_delta_deg1)
@expression(model, soh2_fluct, soh2_fluct_init - power_delta_deg2)
@expression(model, soh3_fluct, soh3_fluct_init - power_delta_deg3)

"# NOTE: SOH is only meaningful if it appears in the objective 
# (then SOH = min(soh1, soh2)). 
# If SOH is not part of the objective, remove it entirely to avoid slack."
# @variable( model, SOH )
# @constraint(model, SOH <= soh1)
# @constraint(model, SOH <= soh2)

# === Component-wise SOH variables (worst per degradation type) ===
@variable(model, SOH_ramping)
@constraint(model, SOH_ramping <= soh1_ramping)
@constraint(model, SOH_ramping <= soh2_ramping)
@constraint(model, SOH_ramping <= soh3_ramping)


@variable(model, SOH_run)
@constraint(model, SOH_run <= soh1_run)
@constraint(model, SOH_run <= soh2_run)
@constraint(model, SOH_run <= soh3_run)

@variable(model, SOH_fluct)
@constraint(model, SOH_fluct <= soh1_fluct)
@constraint(model, SOH_fluct <= soh2_fluct)
@constraint(model, SOH_fluct <= soh3_fluct)

# === Objective: Maximize Hydrogen Production ===
@objective(model, Max,
    weights.w1 * sum(H2_s1[t] + H2_s2[t] + H2_s3[t] for t in history+1:NT) +
    weights.w2 * (  + weights.w3*SOH_ramping 
                    + weights.w4*SOH_run 
                    + weights.w5*SOH_fluct)
)

return model, P_s1, P_s2, P_s3, H2_s1, H2_s2, H2_s3, z1_OFF, z2_OFF, z3_OFF, soh1_ramping, soh2_ramping, soh3_ramping,
          soh1_run,  soh2_run, soh3_run,
          soh1_fluct, soh2_fluct,soh3_fluct
end