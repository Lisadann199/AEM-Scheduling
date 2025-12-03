using CSV, DataFrames
using Plots


include(raw"C:\Users\lisadan\OneDrive - Danmarks Tekniske Universitet\12_Research\05_AEM_electrolyzer\03_code\AEM-Scheduling\send_enapter_commands.jl")

df_mpc = CSV.read("test_0112\\mpc_results_4hour_test_0112.csv",DataFrame)
# Stack 342A (s1)
df_H2_s1 = filter(row ->
    row.source == "model" &&
    row.varname == "H2_s1" &&
    row.t == 2,
    df_mpc)

df_z1 = filter(row ->
    row.source == "model" &&
    row.varname == "z1_on" &&
    row.t == 2,
    df_mpc)

# Convert both columns to Float64
H2_vals_s1 = parse.(Float64, df_H2_s1.value)
z_vals_s1  = parse.(Float64, df_z1.value)

df_model_s1 = DataFrame(
    timestamp = df_H2_s1.timestamp,
    H2_model = H2_vals_s1 .* z_vals_s1,
)


# Stack A568 (s2)
df_H2_s2 = filter(row ->
    row.source == "model" &&
    row.varname == "H2_s2" &&
    row.t == 2,
    df_mpc)

df_z2 = filter(row ->
    row.source == "model" &&
    row.varname == "z2_on" &&
    row.t == 2,
    df_mpc)

H2_vals_s2 = parse.(Float64, df_H2_s2.value)
z_vals_s2  = parse.(Float64, df_z2.value)

df_model_s2 = DataFrame(
    timestamp = df_H2_s2.timestamp,
    H2_model = H2_vals_s2 .* z_vals_s2,
)


df_meas_s1 = get_historic_data(
    READING_TOKEN;
    device_id = STACKS["342A"],
    attribute = "h2_flow",
    from = "2025-12-01T14:04:00Z",
    to   = "2025-12-01T18:10:59Z",
    granularity = "1m",
    aggregation = "avg"
)

df_meas_s2 = get_historic_data(
    READING_TOKEN;
    device_id = STACKS["A568"],
    attribute = "h2_flow",
    from = "2025-12-01T14:04:00Z",
    to   = "2025-12-01T18:10:59Z",
    granularity = "1m",
    aggregation = "avg"
)

plt = plot(
    layout = (2,1),
    size = (900, 900),
    titlefont = 12,
    legendfontsize = 9,
)

# ---------------------------
# STACK 342A
# ---------------------------
plot!(
    plt[1],
    df_meas_s1.timestamp,#.- Hour(1),
    df_meas_s1.value,
    label = "Measured H₂ Flow 342A",
    lw = 2,
)

plot!(
    plt[1],
    df_model_s1.timestamp,
    df_model_s1.H2_model,
    label = "MPC Estimated H₂ (t=1) 342A",
    lw = 3,
    ls = :dash,
    seriestype = :step,
)

xlabel!(plt[1], "Time")
ylabel!(plt[1], "H₂ Flow NL/h")
title!(plt[1], "Stack 342A: Measured vs MPC Estimated H₂ Flow")

# ---------------------------
# STACK A568
# ---------------------------
plot!(
    plt[2],
    df_meas_s2.timestamp,
    df_meas_s2.value,
    label = "Measured H₂ Flow A568",
    lw = 2,
)

plot!(
    plt[2],
    df_model_s2.timestamp,
    df_model_s2.H2_model,
    label = "MPC Estimated H₂ (t=1) A568",
    lw = 3,
    ls = :dash,
    seriestype = :step,
)

xlabel!(plt[2], "Time")
ylabel!(plt[2], "H₂ Flow NL/h")
title!(plt[2], "Stack A568: Measured vs MPC Estimated H₂ Flow")

display(plt)