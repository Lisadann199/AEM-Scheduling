using Dates

"""
Mock version of read_measurement().
Special rule: if measured_variable == "errors_exists", return false.
"""
function mock_read_measurement(device_id, measured_variable, READING_TOKEN)

    if measured_variable == "errors_exists"
        println("[MOCK] read_measurement($device_id, errors_exists) -> false")
        return false, now()
    end

    # Fake numeric measurement (e.g., flow, power, pressure, etc.)
    fake_value = rand() * 100
    fake_timestamp = now()

    println("[MOCK] read_measurement($device_id, $measured_variable) -> $fake_value at $fake_timestamp")

    return fake_value, fake_timestamp
end


val, ts = mock_read_measurement("342A", "errors_exists", "dummy")
# -> false, current timestamp

val, ts = mock_read_measurement("342A", "h2_flow", "dummy")
# -> random measurement, current timestamp

function mock_send_command(stack_name::String, command_name::String, value=nothing)
    # Check if stack exists
    if !haskey(STACKS, stack_name)
        throw(ArgumentError("Stack $stack_name not found."))
    end

    # Build fake payload exactly like real function
    payload = Dict{String,Any}(
        "device_id" => STACKS[stack_name],
        "command_name" => command_name
    )

    if value !== nothing
        payload["arguments"] = Dict("value" => round(Float64(value), digits=1))
    end

    # Print what would happen
    timestamp = Dates.format(now(), "HH:MM:SS")
    println("timestamp: [MOCK] Command sent: $(payload)")

    # Create a realistic mock API response
    mock_response = Dict(
        "status" => "ok",
        "device_id" => STACKS[stack_name],
        "command" => command_name,
        "arguments" => get(payload, "arguments", nothing),
        "timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")
    )

    println("[MOCK] Response: ", mock_response)

    return mock_response
end


mock_send_command("342A","start")