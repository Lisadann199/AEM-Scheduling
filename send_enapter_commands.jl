using HTTP
using JSON
using Dates
using CSV
using DataFrames
using Base.Threads
using JSON3
# === Config
const READING_TOKEN =  "581408ee84d069773e77b51e07d8bec6c0700a9358f2cc126e63de16353b079f" # lisas token used for reading
const SEND_TOKEN = "fd25d83b0d6dd1447f9454b16d22259ba2084c2d11e337587100b6fc0ddac8c7" # marius token used for sending commands
#LISA2_TOKEN = "fe746a1c9426796579b1ac2a7696cd118d568df464ffaa00476b62b544c0b2a1"
const BROKER_IP = "172.18.5.105"
const COMMAND_ENDPOINT = "http://$BROKER_IP/api/commands/v1/execute"

# === Device IDs for each stack
STACKS = Dict(
    "342A" => "29ee3293-8b22-4693-a031-b600d9c83c21",
    "A568" => "3a0747d1-3540-48ef-8c8f-348ef94ec0d4",
    "AD7F" => "2f6d995a-1142-4726-a574-93bd4857d011"
)

# List of commands
commands = Dict(
    "set_production_rate" => true,
    "start" => false,
    "stop" => false,
    "reset" => false,
    "force_water_filling" => false,
    "preheat" => false,
    "stop_preheat" => false
)

function send_command(stack_name::String, command_name::String, value=nothing)
    # Check if stack exists
    if !haskey(STACKS, stack_name)
        throw(ArgumentError("Stack $stack_name not found."))
    end

    # Build payload
    payload = Dict{String,Any}(
        "device_id" => STACKS[stack_name],
        "command_name" => command_name
    )

    if value !== nothing
        payload["arguments"] = Dict("value" => round(Float64(value), digits=1))
    end

    # Headers
    headers = [
        "X-Enapter-Auth-Token" => SEND_TOKEN,
        "Content-Type" => "application/json"
    ]

    try
        # Send POST request
        response = HTTP.post(
            COMMAND_ENDPOINT,
            headers,
            JSON.json(payload)
        )

        # Print info
        timestamp = Dates.format(now(), "HH:MM:SS")
        println("timestamp: Command sent: $(payload)")

        # Read body ONCE
        body_str = String(response.body)
        println("Response: ", body_str)

        # Return parsed JSON (or nothing if empty)
        return isempty(body_str) ? nothing : JSON.parse(body_str)


    catch e
        println("Failed to send command: $e")
        return nothing
    end
end

# function run_scheduled_commands(filepath::String)

#     # Read CSV (skip 2nd row like Python skiprows=[1])
#     df = CSV.read(filepath, DataFrame; skipto=3)

#     # Replace missing values with empty strings
#     foreach(col -> begin
#         if eltype(col) <: Union{Missing, String} && col isa AbstractVector
#             try
#                 replace!(col, missing => "")
#             catch
#                 # ignore columns that cannot be replaced
#             end
#         end
#     end, eachcol(df))
    
#     start_time = time()
#     cumulative_duration = 0.0

#     for row in eachrow(df)
#         # Parse duration or default to 0
#         if row[:duration] == "" || row[:duration] === missing
#             duration = 0.0
#         elseif isa(row[:duration], String)
#             duration = parse(Float64, row[:duration])
#         else
#             duration = Float64(row[:duration])
#         end
#                 cumulative_duration += duration

#         # Loop through columns except excluded ones
#         for col in names(df)
#             if col in ["duration", "commands", "argument"]
#                 continue
#             end

#             if strip(string(row[col])) == "1"
#                 stack_name = uppercase(strip(col))
#                 command_name = row[:commands]
#                 argument = row[:argument]

#                 # Convert argument or use nothing
#                 arg_value = (argument === missing || argument == "") ? nothing :
#                     (isa(argument, String) ? parse(Float64, argument) : Float64(argument))

#                 # Print what will be sent
#                 println("Sending to $stack_name → $command_name", 
#                         arg_value === nothing ? "" : " (value = $arg_value)")

#                 # Run send_command in a separate thread
#                 @spawn send_command(stack_name, command_name, arg_value)
#             end
#         end

#         # Wait until cumulative time is reached
#         elapsed = time() - start_time
#         remaining = cumulative_duration - elapsed
#         if elapsed < cumulative_duration
#             println("Waiting $(round(remaining, digits=2)) seconds until next command...")
#             sleep(cumulative_duration - elapsed)
#         end
#     end
# end

## SEND COMMANDS TO THE ELECTROLYZER
#run_scheduled_commands("schedule-csv-files\\very_short_test.csv")
# send_command("342A","set_production_rate",79.5)
# send_command("342A","stop")

############################################

function get_historic_data(READING_TOKEN;
        device_id,
        attribute,
        from,
        to,
        granularity="1m",
        aggregation="avg"
    )

    # ---- Build request body ----
    body = JSON3.write(Dict(
        "from" => from,
        "to" => to,
        "granularity" => granularity,
        "aggregation" => aggregation,
        "telemetry" => [
            Dict(
                "device" => device_id,
                "attribute" => attribute
            )
        ]
    ))

    # ---- Send request ----
    resp = HTTP.post(
        "https://api.enapter.com/telemetry/v1/timeseries",
        ["X-Enapter-Auth-Token" => READING_TOKEN,
         "Content-Type" => "application/json"],
        body
    )

    raw = String(resp.body)

    # ---- Parse influx-style response into CSV ----
    lines = split(raw, '\n')

    if length(lines) < 2
        error("No data returned from Enapter")
    end

    # Skip first line (header like: "ts,telemetry=h2_flow xxx")
    csv_lines = lines[2:end]
    csv_text = "ts,value\n" * join(csv_lines, '\n')

    # ---- Load into DataFrame ----
    df = CSV.read(IOBuffer(csv_text), DataFrame)

    # ---- Convert timestamp (no timezone correction) ----
    df.timestamp = unix2datetime.(df.ts)

    select!(df, [:timestamp, :value])

    return df
end

df = get_historic_data(
    READING_TOKEN;
    device_id = STACKS["342A"],
    attribute = "h2_flow",
    from = "2025-11-25T09:00:00Z",
    to   = "2025-11-25T17:10:59Z",
    granularity = "1m",
    aggregation = "avg"
)

plot(df.timestamp, df.value)



function read_measurement(device_id, measured_variable, READING_TOKEN)
    resp = HTTP.get(
        "https://api.enapter.com/telemetry/v1/now?devices[$device_id]=$measured_variable",
        ["X-Enapter-Auth-Token" => READING_TOKEN]
    )

    raw = String(resp.body)   # <-- read ONCE

    println("RAW = $raw")     # safe

    if isempty(raw)
        error("Empty response body")
    end

    data = JSON3.read(raw)

    dev = data.devices[device_id]
    entry = getproperty(dev, Symbol(measured_variable))

    value = entry.value
    ts = entry.timestamp
    dt = unix2datetime(ts)   # <-- convert here

    return value, dt
end

# read_measurement(STACKS["342A"],"production_rate",READING_TOKEN)
# read_measurement(STACKS["342A"],"stack_cycles",READING_TOKEN)
# read_measurement(STACKS["342A"],"errors_exists",READING_TOKEN)
# read_measurement(STACKS["342A"],"status",READING_TOKEN)
