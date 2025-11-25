function group_dict(d::Dict{String, Float64})
    # First, collect variable names and their indices
    index_map = Dict{String, Vector{Tuple{Int, Float64}}}()

    for (key, value) in d
        m = match(r"^([^\[]+)\[(\d+)\]$", key)
        if m !== nothing
            var_name = m.captures[1]
            index = parse(Int, m.captures[2])

            if !haskey(index_map, var_name)
                index_map[var_name] = Vector{Tuple{Int, Float64}}()
            end
            push!(index_map[var_name], (index, value))
        end
    end

    # Now convert to array format
    grouped = Dict{String, Vector{Union{Missing, Float64}}}()
    for (var_name, entries) in index_map
        max_idx = maximum(first.(entries))
        arr = Vector{Union{Missing, Float64}}(undef, max_idx)
        fill!(arr, missing)
        for (i, val) in entries
            arr[i] = val
        end
        grouped[var_name] = arr
    end

    return grouped
end


function scale_to_range(vec, ElCap)
    min_val = minimum(vec)
    max_val = maximum(vec)
    return (3*ElCap*(1/0.9)) .* (vec .- min_val) ./ (max_val - min_val)
end;


function group_dict(d::Dict{String, Float64})
    index_map = Dict{String, Vector{Tuple{Int, Float64}}}()
    scalar_map = Dict{String, Float64}()

    for (key, value) in d
        m = match(r"^([^\[]+)\[(\d+)\]$", key)
        if m !== nothing
            var_name = m.captures[1]
            index = parse(Int, m.captures[2])

            if !haskey(index_map, var_name)
                index_map[var_name] = Vector{Tuple{Int, Float64}}()
            end
            push!(index_map[var_name], (index, value))
        else
            # No match → scalar variable like "soh1"
            scalar_map[key] = value
        end
    end

    grouped = Dict{String, Vector{Union{Missing, Float64}}}()
    for (var_name, entries) in index_map
        max_idx = maximum(first.(entries))
        arr = Vector{Union{Missing, Float64}}(undef, max_idx)
        fill!(arr, missing)
        for (i, val) in entries
            arr[i] = val
        end
        grouped[var_name] = arr
    end

    # Add scalars as 1-element vectors (or keep as Float64 if you prefer)
    for (k,v) in scalar_map
        grouped[k] = [v]  # wrap in vector for consistency
    end

    return grouped
end


function group_dict(d::Dict{String, Float64})
    index_map = Dict{String, Vector{Tuple{Tuple{Vararg{Int}}, Float64}}}()
    scalar_map = Dict{String, Float64}()

    for (key, value) in d
        # Match variables like "name[1]" or "name[3,2]"
        m = match(r"^([^\[]+)\[([0-9,]+)\]$", key)
        if m !== nothing
            var_name = m.captures[1]
            idx_str = m.captures[2]
            idx = Tuple(parse.(Int, split(idx_str, ",")))  # tuple of indices

            if !haskey(index_map, var_name)
                index_map[var_name] = Vector{Tuple{Tuple{Vararg{Int}}, Float64}}()
            end
            push!(index_map[var_name], (idx, value))
        else
            # No brackets → scalar variable like "soh1" or "soh_gap"
            scalar_map[key] = value
        end
    end

    grouped = Dict{String, Any}()

    # Handle arrays
    for (var_name, entries) in index_map
        if length(first(entries)[1]) == 1
            # 1D array
            max_idx = maximum(i[1] for (i,_) in entries)
            arr = Vector{Union{Missing,Float64}}(missing, max_idx)
            for (i, val) in entries
                arr[i[1]] = val
            end
            grouped[var_name] = arr
        else
            # 2D array
            max_i = maximum(i[1] for (i,_) in entries)
            max_j = maximum(i[2] for (i,_) in entries)
            arr = Matrix{Union{Missing,Float64}}(missing, max_i, max_j)
            for (i, val) in entries
                arr[i...] = val
            end
            grouped[var_name] = arr
        end
    end

    # Add scalars
    for (k,v) in scalar_map
        grouped[k] = v
    end

    return grouped
end
