# the code to generate a milp model with operating constraints for the AEM Electrolyzer

# === MODEL === 
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
for t in min_off_time:NT
    @constraint(model, sum(z1_SB[i] for i in (t - min_off_time + 1):t) <= 11)
    @constraint(model, sum(z2_SB[i] for i in (t - min_off_time + 1):t) <= 11)
end

# === power ===
@variable(model, 0 <= P_s1[t=1:NT] <= ElCap)
@variable(model, 0 <= P_s2[t=1:NT] <= ElCap)

# === Power balance constraint ===
@constraint(model, [t=1:NT], P_s1[t] + P_s2[t] <= Power_wind[t])

# === Setpoints ===
@variable(model, setpoint_s1[t=1:NT] >= 0)   # in percent (60–100)
@variable(model, setpoint_s2[t=1:NT] >= 0)

# === Enforce linear fit ONLY when ON ===

a = 0.0250818060738514
b = -0.1901347621495934
min_power = (a * 60+ b)
# === STACK LOGIC ===
@constraint(model, [t=1:NT], P_s1[t] >= min_power* z1_on[t])
@constraint(model, [t=1:NT], P_s2[t] >= min_power* z2_on[t])

@constraint(model, [t=1:NT], P_s1[t] <= ElCap * z1_on[t])
@constraint(model, [t=1:NT], P_s2[t] <= ElCap * z2_on[t])

@constraint(model, [t=1:NT], P_s1[t] == (a * setpoint_s1[t] + b) )
@constraint(model, [t=1:NT], P_s2[t] == (a * setpoint_s2[t] + b) )

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

min_off_time = 12 # 5 minute timesteps 12 timesteps => 1 hour
for t in (min_off_time+1):NT # Normal case: enforce min 12 consecutive OFFs for t >= 13
    @constraint(model, 12.0*z1_cold_start[t] <= sum(z1_OFF[t - min_off_time : t - 1]))
    @constraint(model, 12.0*z2_cold_start[t] <= sum(z2_OFF[t - min_off_time : t- 1]))
end

# Startup rule for the first 12 timesteps
for t in 2:min_off_time
    @constraint(model, 12.0 * z1_cold_start[t] <= sum(z1_OFF[1:t-1]) + (min_off_time - (t-1)))
    @constraint(model, 12.0 * z2_cold_start[t] <= sum(z2_OFF[1:t-1]) + (min_off_time - (t-1)))
end

H_coeff = 5.0   # NL/h per percentage point

@expression(model, H2_s1[t=1:NT] , H_coeff*setpoint_s1[t] )
@expression(model, H2_s2[t=1:NT] , H_coeff*setpoint_s2[t] )


@objective(model, Max, sum(H2_s1[t] + H2_s2[t] for t in 1:NT))
#@objective(model, Max, sum(P_s1[t] + P_s2[t] for t in 1:NT))
