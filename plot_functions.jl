function heatmap_schedule(z1_on_vals::Vector{<:Int},
    z2_on_vals::Vector{<:Int},
    z3_on_vals::Vector{<:Int},
    z1_OFF_vals::Vector{<:Int},
    z2_OFF_vals::Vector{<:Int},
    z3_OFF_vals::Vector{<:Int},
    NT,tick_pos,tick_labels)

# # === Compute stack states numerically ===
# 0 = off, 1 = standby, 2 = on
state1 = [z1_on_vals[t] == 1 ? 2 :  (z1_OFF_vals[t] == 1 ? 0 : -1) for t in 1:NT];
state2 = [z2_on_vals[t] == 1 ? 2 :  (z2_OFF_vals[t] == 1 ? 0 : -1) for t in 1:NT];
state3 = [z3_on_vals[t] == 1 ? 2 :  (z3_OFF_vals[t] == 1 ? 0 : -1) for t in 1:NT];

# === Combine into a matrix ===
Z = vcat(state1', state2', state3') ; # size: 2 x NT

# tick_pos   = (1:35.9:NT+1) ./ 12  ;
# tick_labels = [i == 24 ? "24:00" : Dates.format(Time(0) + Hour(i), "HH:MM") for i in 0:3:24];

# === Plot heatmap ===
plt = heatmap(collect(1:NT) ./ 12, ["Stack 1", "Stack 2", "Stack 3"], Z;
    color=cgrad([:gray, :red, :orange, :green]),
    colorbar=false,
    #xlabel="Date and Time",
    yflip=true,
    grid = false,
    xticks= (tick_pos, tick_labels),
    framestyle= :box,
    #size=(1000, 300),
    clims=(-1, 2),          # <--- FIXED color range
    extra_kwargs = Dict(
        "shader" => "interp",        # smooth shading
        "mesh/ordering" => "colwise",
        "point meta" => "explicit",  # use explicit metadata
        "patch type" => "rectangle" # raster-style patches
    )
    );
#display(plt)

return plt
end


# Function to step-duplicate a vector
function steppostify(x::Vector, y::Vector)
    x2 = Vector{eltype(x)}()
    y2 = Vector{eltype(y)}()
    for i in 1:length(x)-1
        push!(x2, x[i])
        push!(x2, x[i+1])
        push!(y2, y[i])
        push!(y2, y[i])
    end
    # Add last point
    push!(x2, x[end])
    push!(y2, y[end])
    return x2, y2
end;

function add_shading!(plt, time::Vector{Float64}, b_vals::Vector{Int},shade_color::Any)
    NT = length(b_vals)
    dt = time[2] - time[1]

    in_block = false
    start_idx = 0

    for i in 1:NT
        if b_vals[i] == 1 && !in_block
            in_block = true
            start_idx = i
        elseif (b_vals[i] == 0 || i == NT) && in_block
            in_block = false
            end_idx = i - 1
            if b_vals[i] == 1 && i == NT
                end_idx = i
            end

            t_start = time[start_idx]
            t_end = end_idx < NT ? time[end_idx + 1] : time[end_idx] + dt

            vspan!(plt, [t_start, t_end]; color = shade_color, alpha = 0.2, label = "", linewidth = 0)
        end
    end
end;

function individual_power_plot(P_s1_vals,P_s2_vals,P_s3_vals,z1_on_vals,z2_on_vals,z3_on_vals,NT,ElCap,tick_pos,tick_labels)

# tick_pos   = (1:35.9:NT+1) ./ 12  ;
# tick_labels = [i == 24 ? "24:00" : Dates.format(Time(0) + Hour(i), "HH:MM") for i in 0:3:24];

# # === Plot the Power ===

z1_vals = [round(Int, value(z1_on_vals[t])) for t in 1:NT];
z2_vals = [round(Int, value(z2_on_vals[t])) for t in 1:NT];
z3_vals = [round(Int, value(z3_on_vals[t])) for t in 1:NT];


b_vals = [Int(z1_vals[t] * z2_vals[t]* z3_vals[t]) for t in 1:NT];

time = collect(1:NT) ./ 12;

# Prepare the base plots
p1 = plot(time, P_s1_vals ./ ElCap .* 100.0,
    label = "Stack 1",
    ylabel = "Power [% Pₙₒₘ]",
    #xlabel = "Date and Time",
    xticks = (tick_pos, tick_labels),
    # legend = :topright,
    legend = false,
    title="Stack 1",
    framestyle = :box,
    grid = false,
    xtickfont = font(10, "Arial"),
    ytickfont = font(10, "Arial"),
    guidefont = font(12, "Arial", :bold),
    titlefont = font(13, "Arial", :bold),
    linetype=:steppost
);

p2 = plot(time, P_s2_vals ./ ElCap .* 100.0,
    label = "Stack 2",
    ylabel = "Power [% Pₙₒₘ]",
    #xlabel = "Date and Time",
    xticks = (tick_pos, tick_labels),
        # legend = :topright,
    legend = false,
    title="Stack 2",
    framestyle = :box,
    grid = false,
    xtickfont = font(10, "Arial"),
    ytickfont = font(10, "Arial"),
    guidefont = font(12, "Arial", :bold),
    titlefont = font(13, "Arial", :bold),
    linetype=:steppost
);

p3 = plot(time, P_s3_vals ./ ElCap .* 100.0,
    label = "Stack 2",
    ylabel = "Power [% Pₙₒₘ]",
    #xlabel = "Date and Time",
    xticks = (tick_pos, tick_labels),
    # legend = :topright,
    legend = false,
    title="Stack 3",
    framestyle = :box,
    grid = false,
    xtickfont = font(10, "Arial"),
    ytickfont = font(10, "Arial"),
    guidefont = font(12, "Arial", :bold),
    titlefont = font(13, "Arial", :bold),
    linetype=:steppost
);


add_shading!(p1, time, b_vals, :grey)
add_shading!(p2, time, b_vals, :grey)
add_shading!(p3, time, b_vals, :grey)

# Combine the two plots
Power_plot = plot(p1, p2, p3, layout = (3, 1))
#display(Power_plot)

return Power_plot

end

function layered_power_plot(P_s1_vals, P_s2_vals, P_s3_vals,ElCap,Power,NT,tick_pos,tick_labels)
    
# # === Area plots ===
x = 1:NT
time = collect(1:NT) ./ 12;

# Compute cumulative layers
s1 =  P_s1_vals ./ ElCap .* 100.0;
s2 = s1 .+( P_s2_vals ./ ElCap .* 100.0);
s3 = s2 .+ (P_s3_vals./ElCap .*100.0);
unused = (Power./ ElCap .* 100.0) .- s3;
unused = map(x -> max(x, 0.0), unused);
top = s3 .+ unused;

# Generate steppost-style duplicated data
x_step, s1_step = steppostify(time, s1);
_, s2_step = steppostify(time, s2);
_, s3_step = steppostify(time, s3);
_, top_step = steppostify(time, top);

# Plot with formatting
Layered_plt = plot(
    x_step, top_step, fillrange=s3_step, seriestype=:path, lw=0, label="curtailment", fillalpha=0.3,
   # color = :blue,
    #xlabel = "Date and Time",
    xticks = (tick_pos, tick_labels),
    legend = :topright,
    framestyle = :box,
    grid = false,
    # xtickfont = font(10, "Arial"),
    # ytickfont = font(10, "Arial"),
    # guidefont = font(12, "Arial", :bold),
    # titlefont = font(13, "Arial", :bold),
    ylabel = L"\mathrm{Power}\;[\%\; \mathrm{P}_{\mathrm{nom}, \;\mathrm{stack}}]"
);

plot!(
    x_step, s3_step, fillrange=s2_step, seriestype=:path, lw=0, label="Stack 3", fillalpha=0.5, color = :purple
);
plot!(
    x_step, s2_step, fillrange=s1_step, seriestype=:path, lw=0, label="Stack 2", fillalpha=0.7, color = :orange
);

plot!(
    x_step, s1_step, fillrange=0, seriestype=:path, lw=0, label="Stack 1", fillalpha=0.5, color = :green
    )
#display(Layered_plt)

return Layered_plt
    
end

function layered_production_plot(H2_s1, H2_s2,NT,tick_pos,tick_labels)
    
# # === Area plots ===
x = 1:NT
time = collect(1:NT) ./ 12;

# Compute cumulative layers
s1 =  H2_s1 ;
s2 = s1 .+( H2_s2 );
# unused = (Power./ ElCap .* 100.0) .- s2;
# unused = map(x -> max(x, 0.0), unused);
# top = s2 .+ unused;

# Generate steppost-style duplicated data
x_step, s1_step = steppostify(time, s1);
_, s2_step = steppostify(time, s2);
#_, top_step = steppostify(time, top);

# Plot with formatting
Layered_plt = plot(
   x_step, s2_step, fillrange=s1_step, seriestype=:path, lw=0, label="Stack 2", fillalpha=0.3,
    color = :purple,
   # xlabel = "Date and Time",
    xticks = (tick_pos, tick_labels),
    legend = :topright,
    framestyle = :box,
    grid = false,
    xtickfont = font(10, "Arial"),
    ytickfont = font(10, "Arial"),
    guidefont = font(12, "Arial", :bold),
    titlefont = font(13, "Arial", :bold),
    ylabel = L"\mathrm{H_2 \; Production}\;[\mathrm{kg/h}]"
);

# plot!(
#     x_step, s2_step, fillrange=s1_step, seriestype=:path, lw=0, label="Stack 2", fillalpha=0.5, color = :purple
# );

plot!(
    x_step, s1_step, fillrange=0, seriestype=:path, lw=0, label="Stack 1", fillalpha=0.7, #color = :lightgreen
    )
#display(Layered_plt)

return Layered_plt
    
end

function plot_soh(x, soh1, soh2; xticks=nothing, title::String, ylabel::String)
    plt = plot(
        x, soh1,
        label = "Stack 1",
        linewidth = 2,
        color = :blue,
        xlabel = "Day of Year",
        ylabel = ylabel,
        title  = title,
        legend = :topright,
        grid   = :on,
        framestyle = :box,
        xticks = xticks,
    )
    plot!(plt, x, soh2,
        label = "Stack 2",
        linewidth = 2,
        color = :red,
        linestyle = :dash,
    )
    return plt
end

"""
    plot_cumsum(time, vec1, vec2; seriestype=:line, label1="Stack 1", label2="Stack 2", title="")

Make a cumulative sum plot of two input vectors over `time`.

- `vec1`, `vec2`: vectors to be cumulatively summed.
- `time`: x-axis (e.g. 1:NT).
- `seriestype`: plotting style (`:line`, `:steppost`, …).
- `label1`, `label2`: legend labels.
- `title`: plot title.
"""
function plot_cumsum(time, vec1, vec2;
                     seriestype=:steppost,
                     label1="Stack 1",
                     label2="Stack 2",
                     title="")
    
    
    # helper: keep only points where vec changes
    compress_steps(t, v) = begin
        keep = [1; findall(diff(v) .!= 0) .+ 1]   # first point + change points
        return t[keep], v[keep]
    end

    # cumulative sums
    c1 = cumsum(vec1)
    c2 = cumsum(vec2)

    # compress
    t1, c1c = compress_steps(time, c1)
    t2, c2c = compress_steps(time, c2)

    # plot
    plt = plot(t1, c1c;
        seriestype=seriestype,
        label=label1,
        title=title,
        xlabel="Time",
        ylabel="Cumulative sum",
        linewidth=2,
        legend = :topleft,
        grid   = :on,
        framestyle = :box,
    )
    plot!(plt, t2, c2c;
        seriestype=seriestype,
        label=label2,
        linewidth=2,
        linestyle=:dash,
    )

    return plt
end