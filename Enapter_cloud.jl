using HTTP
using JSON
using Dates

const GATEWAY_IP = "172.18.5.105" 
const BASE_URL = "http://$GATEWAY_IP/api"
const TOKEN    = "e4408442d08708a99878b46b6fe36cdf44d36df2bbc3a0f9fdfbd29e74838147"

# helper to build headers
function headers()
    return ["X-Enapter-Auth-Token" => TOKEN,
            "Accept" => "application/json"]
end

# Get list of devices
function list_devices()
    url = "$BASE_URL/assets/v1/devices"
    resp = HTTP.get(url; headers=headers())
    if resp.status == 200
        return JSON.parse(String(resp.body))
    else
        error("Error listing devices: status=$(resp.status) body=$(String(resp.body))")
    end
end

# Get telemetry for a device in a time range
function get_telemetry(device_id::String; from::DateTime, to::DateTime, limit::Int=1000)
    fmt = dateformat"yyyy-mm-ddTHH:MM:SSZ"
    from_s = Dates.format(from, fmt)
    to_s   = Dates.format(to,   fmt)
    url = "$BASE_URL/telemetry/v1/devices/$device_id/data?from=$from_s&to=$to_s&limit=$limit"
    resp = HTTP.get(url; headers=headers())
    if resp.status == 200
        return JSON.parse(String(resp.body))
    else
        error("Error fetching telemetry: status=$(resp.status) body=$(String(resp.body))")
    end
end

# Usage example
devs = list_devices()
println("Devices: ", devs)

# Suppose we found a device ID
device_id = devs["devices"][1]["id"]  # adjust path based on JSON structure
data = get_telemetry(device_id; from=now()-Hour(1), to=now(), limit=500)
println("Telemetry: ", data)
