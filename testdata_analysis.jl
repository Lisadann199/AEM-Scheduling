using CSV
using DataFrames
using Dates
using Plots
using LaTeXStrings

# ---------------------------------------------------------------
# DATA OVERVIEW
#
# df342A, dfA568, dfAD7F  -> Measured electrolyzer data (Enapter Cloud)
#   timestamp      : measurement time
#   HASS_in_a      : measured stack current (A)
#   PSU_in_v       : measured stack voltage (V)  (used for DC power)
#   PSU_out_v      : voltage setpoint (control target) (not a measurement)
#   stack_power_kW = PSU_in_v * HASS_in_a / 1000
#
# dfSimulation -> Model / simulation results
#   timestamp      : simulation time
#   P_s1, P_s2, P_s3 : simulated stack power for stacks 1–3
#
# df_eddk_data -> Data from Energydata.dk
#   Stack voltage columns:
#       "EL_2A26_stack_voltage | electrolyzer_2A26/stack_voltage | 804052"
#       "EL_3492_stack_voltage | electrolyzer_3492/stack_voltage | 804070"
#       "EL_ADD4_stack_voltage | electrolyzer_ADD4/stack_voltage | 804088"
#
#   Stack current columns:
#       "EL_2A26_stack_amperage | electrolyzer_2A26/stack_amperage | 804050"
#       "EL_3492_stack_amperage | electrolyzer_3492/stack_amperage | 804068"
#       "EL_ADD4_stack_amperage | electrolyzer_ADD4/stack_amperage | 804086"
#
#   Computed power (in code):
#       EL_xxx_power_kW = stack_voltage * stack_current / 1000
#
# ---------------------------------------------------------------

gr()
df342A = CSV.read("test_2511\\electrolyser_el21_342A4045C953B949B957E3B5B0946D5A964EDFDE_12121.csv", DataFrame)
dfA568 = CSV.read("test_2511\\electrolyser_el21_AD7F038191AC7F26612396BD65EC74740258D8CA_12122.csv", DataFrame)
dfAD7F = CSV.read("test_2511\\electrolyser_el21_A568B1F1615820619D52C4C9A07D466223CFD5EF_12124.csv", DataFrame)
dfSimulation = CSV.read("test_2511\\acc_2511.csv",DataFrame)
df_eddk_data = CSV.read("test_2511\\Energydata export 26-11-2025 11-58-49.csv", DataFrame)

for df in [df342A, dfA568, dfAD7F]
    df.timestamp = DateTime.(df.timestamp, dateformat"yyyy-mm-dd HH:MM:SS +0000")
    sort!(df, :timestamp)
end

for df in [df_eddk_data ]
    df.ts = DateTime.(df.ts, dateformat"yyyy-mm-dd HH:MM:SS")
    sort!(df, :ts)
end

voltage_cols = [
    "EL_2A26_stack_voltage | electrolyzer_2A26/stack_voltage | 804052",
    "EL_3492_stack_voltage | electrolyzer_3492/stack_voltage | 804070",
    "EL_ADD4_stack_voltage | electrolyzer_ADD4/stack_voltage | 804088"
]

amperage_cols = [
    "EL_2A26_stack_amperage | electrolyzer_2A26/stack_amperage | 804050",
    "EL_3492_stack_amperage | electrolyzer_3492/stack_amperage | 804068",
    "EL_ADD4_stack_amperage | electrolyzer_ADD4/stack_amperage | 804086"
]

tags = ["2A26", "3492", "ADD4"]

for (vcol, acol, tag) in zip(voltage_cols, amperage_cols, tags)
    power_col = Symbol("EL_$(tag)_power_kW")
    df_eddk_data[!, power_col] = df_eddk_data[!, vcol] .* df_eddk_data[!, acol] ./ 1000
end

# Calculate DC Power
# df342A.stack_power_kW = df342A.PSU_out_v .* df342A.HASS_in_a ./100
# dfA568.stack_power_kW = dfA568.PSU_out_v .* dfA568.HASS_in_a ./ 1000
# dfAD7F.stack_power_kW = dfAD7F.PSU_out_v .* dfAD7F.HASS_in_a ./ 1000

df342A.stack_power_kW  = df342A.PSU_in_v .* df342A.HASS_in_a ./ 1000
dfA568.stack_power_kW  = dfA568.PSU_in_v .* dfA568.HASS_in_a ./ 1000
dfAD7F.stack_power_kW  = dfAD7F.PSU_in_v .* dfAD7F.HASS_in_a ./ 1000

start_time = DateTime("2025-11-25 11:10:23", dateformat"yyyy-mm-dd HH:MM:SS")
end_time = DateTime("2025-11-25 17:50:00", dateformat"yyyy-mm-dd HH:MM:SS")

H2_flow_s1_342A = dfSimulation[!,"H2_s1"].*dfSimulation[!,"z1_on"]
H2_flow_s2_A568 = dfSimulation[!,"H2_s2"].*dfSimulation[!,"z2_on"]
H2_flow_s3_AD7F = dfSimulation[!,"H2_s3"].*dfSimulation[!,"z3_on"]
sp_timestampsno  = start_time:Minute(5):start_time + Minute(5)*(length(H2_flow_s1_342A)-1)
dfSimulation.timestamp = collect(sp_timestamps)

# Plotting:
xmin = DateTime("2025-11-25 11:10:00", dateformat"yyyy-mm-dd HH:MM:SS")
xmax = DateTime("2025-11-25 17:10:00", dateformat"yyyy-mm-dd HH:MM:SS")
hour_ticks = start_time:Hour(1):end_time

## H2 flow 
# --- Stack 1 (342A) ---
p1 = plot(df342A.timestamp, df342A.h2_flow,
          xticks=(hour_ticks, Dates.format.(hour_ticks, "HH:MM")),
          xlims=(xmin, xmax),
          xrotation=45,
          ylabel="H₂ Flow (Nl/min)",
          title="Stack 1 (342A)",
          label="Measurement",
          legend =:topright)

plot!(p1, dfSimulation.timestamp, H2_flow_s1_342A,
      linewidth=0.7,
      linetype=:step,
      label="Simulation")

# --- Stack 2 (AD7F) ---
p2 = plot(dfAD7F.timestamp, dfAD7F.h2_flow,
          xticks=(hour_ticks, Dates.format.(hour_ticks, "HH:MM")),
          xlims=(xmin, xmax),
          xrotation=45,
          ylabel="H₂ Flow (Nl/min)",
          title="Stack 2 (A568)",
          label="Measurement",
          legend =:topright)

plot!(p2, dfSimulation.timestamp, H2_flow_s2_A568,
      linewidth=0.7,
      linetype=:step,
      label="Simulation")

# --- Stack 3 (A568) ---
p3 = plot(dfA568.timestamp, dfA568.h2_flow,
          xticks=(hour_ticks, Dates.format.(hour_ticks, "HH:MM")),
          xlims=(xmin, xmax),
          xrotation=45,
          ylabel="H₂ Flow (Nl/min)",
          title="Stack 3 (AD7F)",
          label="Measurement",
          legend =:topright)

plot!(p3, dfSimulation.timestamp, H2_flow_s3_AD7F,
      linewidth=0.7,
      linetype=:step,
      label="Simulation")

plot(p1, p2, p3, layout=(3,1), size=(900,800))

p1 = plot(df_eddk_data.ts,
          df_eddk_data.EL_2A26_power_kW,
          xticks=(hour_ticks, Dates.format.(hour_ticks, "HH:MM")),
          xlims=(xmin, xmax),
          xrotation=45,
          ylabel="Power (kW)",
          title="Stack 1 (2A26)",
          label="Measured",
          legend=:topright)

plot!(p1, dfSimulation.timestamp,
      dfSimulation.P_s1,
      linewidth=0.7,
      linetype=:step,
      label="Simulation")

p2 = plot(df_eddk_data.ts,
          df_eddk_data.EL_3492_power_kW,
          xticks=(hour_ticks, Dates.format.(hour_ticks, "HH:MM")),
          xlims=(xmin, xmax),
          xrotation=45,
          ylabel="Power (kW)",
          title="Stack 2 (3492)",
          label="Measured",
          legend=:topright)

plot!(p2, dfSimulation.timestamp,
      dfSimulation.P_s2,
      linewidth=0.7,
      linetype=:step,
      label="Simulation")

# POWER PLOTS
# --- Stack 1 (342A) ---
p1 = plot(df342A.timestamp,
          df342A.PSU_in_v .* df342A.HASS_in_a ./ 1000,
          xticks=(hour_ticks, Dates.format.(hour_ticks,"HH:MM")),
          xlims=(xmin, xmax),
          ylabel="Power (kW)",
          title="Stack 1 (342A)",
          ylims=[-0.1,2.6],
          label="Measured")

plot!(p1,
      dfSimulation.timestamp,
      dfSimulation.P_s1,
      linetype=:step,
      label="Simulation")

# --- Stack 2 (AD7F) ---
p2 = plot(dfAD7F.timestamp,
          dfAD7F.PSU_in_v .* dfAD7F.HASS_in_a ./ 1000,
          xticks=(hour_ticks, Dates.format.(hour_ticks,"HH:MM")),
          xlims=(xmin, xmax),
          xrotation=45,
          ylabel="Power (kW)",
          title="Stack 3 (AD7F)",
           ylims=[-0.1,2.6],
          label="Measured")
plot!(p2,
      dfSimulation.timestamp,
      dfSimulation.P_s2,
      linetype=:step,
      label="Simulation")

# --- Stack 3 (A568) ---
p3 = plot(dfA568.timestamp,
          dfA568.PSU_in_v .* dfA568.HASS_in_a ./ 1000,
          xticks=(hour_ticks, Dates.format.(hour_ticks,"HH:MM")),
          xlims=(xmin, xmax),
          xrotation=45,
          ylabel="Power (kW)",
           ylims=[-0.1,2.6],
          title="Stack 2 (A568)",
          label="Measured")
plot!(p3,
      dfSimulation.timestamp,
      dfSimulation.P_s3,
      linetype=:step,
      label="Simulation")

# --- Show all ---
plot(p1, p2, p3, layout=(3,1), size=(900,800))

for df in [df342A, dfA568, dfAD7F]
    df.errors_exists_binary   = Int.(df.errors_exists)
    df.warnings_exists_binary = Int.(df.warnings_exists)
end

# --- Stack 1 (342A) ---
p1 = plot(df342A.timestamp,
          df342A.errors_exists_binary,
          ylabel="0/1",
          title="Stack 1 (342A)",
          label="Error")

plot!(p1,
      df342A.timestamp,
      df342A.warnings_exists_binary,
      label="Warning")

# --- Stack 2 (A568) ---
p2 = plot(dfA568.timestamp,
          dfA568.errors_exists_binary,
          ylabel="0/1",
          title="Stack 2 (A568)",
          label="Error")

plot!(p2,
      dfA568.timestamp,
      dfA568.warnings_exists_binary,
      label="Warning")

# --- Stack 3 (AD7F) ---
p3 = plot(dfAD7F.timestamp,
          dfAD7F.errors_exists_binary,
          ylabel="0/1",
          title="Stack 3 (AD7F)",
          label="Error")

plot!(p3,
      dfAD7F.timestamp,
      dfAD7F.warnings_exists_binary,
      label="Warning")

# --- Show all three ---
plot(p1, p2, p3, layout=(3,1), size=(900,800))
