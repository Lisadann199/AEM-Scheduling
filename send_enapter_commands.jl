using HTTP
using JSON
using Dates
using CSV
using DataFrames
using Base.Threads
using JSON3
# === Config
#ENAPTER_TOKEN =  "581408ee84d069773e77b51e07d8bec6c0700a9358f2cc126e63de16353b079f" # lisas token
ENAPTER_TOKEN = "fd25d83b0d6dd1447f9454b16d22259ba2084c2d11e337587100b6fc0ddac8c7" # marius token
#LISA2_TOKEN = "fe746a1c9426796579b1ac2a7696cd118d568df464ffaa00476b62b544c0b2a1"
BROKER_IP = "172.18.5.105"
COMMAND_ENDPOINT = "http://$BROKER_IP/api/commands/v1/execute"

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
        "X-Enapter-Auth-Token" => ENAPTER_TOKEN,
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
        println("Response: ", String(response.body))

        # Return parsed JSON
        return JSON.parse(String(response.body))

    catch e
        println("Failed to send command: $e")
        return nothing
    end
end

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
        "X-Enapter-Auth-Token" => ENAPTER_TOKEN,
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

function run_scheduled_commands(filepath::String)

    # Read CSV (skip 2nd row like Python skiprows=[1])
    df = CSV.read(filepath, DataFrame; skipto=3)

    # Replace missing values with empty strings
    foreach(col -> begin
        if eltype(col) <: Union{Missing, String} && col isa AbstractVector
            try
                replace!(col, missing => "")
            catch
                # ignore columns that cannot be replaced
            end
        end
    end, eachcol(df))
    
    start_time = time()
    cumulative_duration = 0.0

    for row in eachrow(df)
        # Parse duration or default to 0
        if row[:duration] == "" || row[:duration] === missing
            duration = 0.0
        elseif isa(row[:duration], String)
            duration = parse(Float64, row[:duration])
        else
            duration = Float64(row[:duration])
        end
                cumulative_duration += duration

        # Loop through columns except excluded ones
        for col in names(df)
            if col in ["duration", "commands", "argument"]
                continue
            end

            if strip(string(row[col])) == "1"
                stack_name = uppercase(strip(col))
                command_name = row[:commands]
                argument = row[:argument]

                # Convert argument or use nothing
                arg_value = (argument === missing || argument == "") ? nothing :
                    (isa(argument, String) ? parse(Float64, argument) : Float64(argument))

                # Print what will be sent
                println("Sending to $stack_name → $command_name", 
                        arg_value === nothing ? "" : " (value = $arg_value)")

                # Run send_command in a separate thread
                @spawn send_command(stack_name, command_name, arg_value)
            end
        end

        # Wait until cumulative time is reached
        elapsed = time() - start_time
        remaining = cumulative_duration - elapsed
        if elapsed < cumulative_duration
            println("Waiting $(round(remaining, digits=2)) seconds until next command...")
            sleep(cumulative_duration - elapsed)
        end
    end
end

## SEND COMMANDS TO THE ELECTROLYZER
run_scheduled_commands("schedule-csv-files\\very_short_test.csv")
send_command("342A","set_production_rate",79.5)
send_command("342A","stop")

############################################

body = JSON3.write(Dict(
    "from" => "2025-11-25T09:00:00Z",
    "to" => "2025-11-25T17:10:59Z",
    "granularity" => "1m",
    "aggregation" => "avg",
    "telemetry" => [
        Dict(
            "device" => STACKS["342A"],
            "attribute" => "h2_flow"
        )
    ]
))

resp = HTTP.post(
    "https://api.enapter.com/telemetry/v1/timeseries",
    ["X-Enapter-Auth-Token" => ENAPTER_TOKEN,
     "Content-Type" => "application/json"],
    body
)

raw = String(resp.body)
lines = split(raw, '\n')
# First line contains "ts,telemetry=h2_flow ..."
data_lines = lines[2:end]
csv_text = "ts,value\n" * join(data_lines, '\n')
df = CSV.read(IOBuffer(csv_text), DataFrame)

df.timestamp = unix2datetime.(df.ts)
select!(df, [:timestamp, :value])

plot(df.value)



using HTTP

token = "YOUR_TOKEN"
for device_id in [STACKS["AD7F"] STACKS["AD7F"] STACKS["342A"]]

resp = HTTP.get(
    "https://api.enapter.com/telemetry/v1/now?devices[$device_id]=errors_exists",
    ["X-Enapter-Auth-Token" => ENAPTER_TOKEN]
)

println(String(resp.body))
end

for device_id in [STACKS["AD7F"] STACKS["AD7F"] STACKS["342A"]]

resp = HTTP.get(
    "https://api.enapter.com/telemetry/v1/now?devices[$device_id]=production_rate",
    ["X-Enapter-Auth-Token" => ENAPTER_TOKEN]
)

println(String(resp.body))
end



payload = JSON3.write( Dict(
    "device_id"     => STACKS["342A"],
    "command_name"  => "set_production_rate",
    "arguments"     => Dict("value" => 77.1)
))

response = HTTP.post(
    COMMAND_ENDPOINT,
    [
        "X-Enapter-Auth-Token" => ENAPTER_TOKEN
    ],
    payload
)


body = """
{
  "from": "2025-11-25T00:00:00Z",
  "to": "2025-11-25T23:59:59Z",
  "granularity": "1h",
  "aggregation": "avg",
  "telemetry": [
    { "device": "$device_id", "attribute": "errors_exists" }
  ]
}
"""
using MQTTClient
using JSON3

broker = "mqtt.enapter.com"
token = ENAPTER_TOKEN
device_id = STACKS["342A"]

client = MQTTClient.Client(broker; username=token)

MQTTClient.connect!(client)

payload = Dict(
    "command" => "set_production_rate",
    "arguments" => Dict("value" => 77.1)
)

topic = "enapter/devices/$device_id/commands"

MQTTClient.publish(client, topic, JSON3.write(payload))

MQTTClient.disconnect!(client)
BROKER_IP = "172.18.5.105"
COMMAND_ENDPOINT = "http://172.18.5.105/api/commands/v1/execute"

POST "http://172.18.5.105/api/commands/v1/execute" HTTP/1.1
X-Enapter-Auth-Token: "581408ee84d069773e77b51e07d8bec6c0700a9358f2cc126e63de16353b079f"
Content-Type: application/json

{
  "device_id": "29ee3293-8b22-4693-a031-b600d9c83c21",
  "command_name": "set_production_rate",
  "arguments": {
    "value": 77
  }
}

curl -X POST "http://172.18.5.105/api/commands/v1/execute?show_progress=true" \
  -H 'X-Enapter-Auth-Token: 581408ee84d069773e77b51e07d8bec6c0700a9358f2cc126e63de16353b079f' \
  -d '{
        "device_id": "9ee3293-8b22-4693-a031-b600d9c83c21",
        "command_name": "set_production_rate",
        "arguments": {
          "value": 77
        }
      }'



      # THIS WORKED TO CHANGE THE SETPOINT:  curl -X POST "http://172.18.5.105/api/commands/v1/execute"  -H "X-Enapter-Auth-Token: fd25d83b0d6dd1447f9454b16d22259ba2084c2d11e337587100b6fc0ddac8c7" -H "Content-Type: application/json" -d "{\"device_id\":\"29ee3293-8b22-4693-a031-b600d9c83c21\",\"command_name\":\"set_production_rate\",\"arguments\":{\"value\":90}}"{"state":"succeeded","payload":{"value":90}}



      using HTTP
      using JSON3
      
      function set_production_rate(local_ip::String, token::String, device_id::String, value::Float64)
          # Ensure value is in allowed range (60–100 for your device)
          if value < 60 || value > 100
              error("Production rate must be between 60 and 100.")
          end
      
          url = "http://$local_ip/api/commands/v1/execute"
      
          payload = Dict(
              "device_id" => device_id,
              "command_name" => "set_production_rate",
              "arguments" => Dict("value" => value)
          )
      
          headers = [
              "X-Enapter-Auth-Token" => ENAPTER_TOKEN,
              "Content-Type" => "application/json"
          ]
      
          response = HTTP.post(url; headers=headers, body=JSON3.write(payload))
      
          return JSON3.read(String(response.body))
      end
      

      LOCAL_IP   = "172.18.5.105"        # your EL local IP

resp = set_production_rate(LOCAL_IP, ENAPTER_TOKEN, STACKS["342A"], 80.0)

println(resp)

using HTTP
using JSON

function set_production_rate(local_ip::String, token::String, device_id::String, value::Float64)

    url = "http://$local_ip/api/commands/v1/execute"

    payload = Dict(
        "device_id" => device_id,
        "command_name" => "set_production_rate",
        "arguments" => Dict("value" => value)
    )

    json_body = JSON.json(payload)   # <- produces same JSON as curl -d

    headers = [
        ("X-Enapter-Auth-Token", token),      # <- 2-tuple is REQUIRED
        ("Content-Type", "application/json")
    ]

    resp = HTTP.post(url, headers, json_body)

    return String(resp.body)
end

git config --global user.name "Lisadann199"
git config --global user.email "lisadannappel63@gmail.com"
