######################################################################################

##################### Australian wind data ###########################################

using CSV, DataFrames, Dates
# Load the CSV file
df_aus = CSV.read("AEMO1213.csv", DataFrame)

# Ensure Date and Time are treated as Strings
df_aus.Date = string.(df_aus.Date)
df_aus.Time = string.(df_aus.Time)

# Combine 'Date' and 'Time' into a single datetime string and parse
df_aus.Timestamp = DateTime.(df_aus.Date .* " " .* df_aus.Time, dateformat"dd/mm/yyyy HH:MM:SS")

# Define the day to plot
target_day = Date(2012, 2, 1) # target_day = Date(YYYY, MM, DD)

# Filter rows for that specific day
df_day = filter(row -> Date(row.Timestamp) == target_day, df_aus)
######################################################################################

##### Danish wind data

using CSV, DataFrames, Dates, Random

# --- Load & parse timestamps --------------------------------------------------
Wind_DK1_2024 = CSV.read("Forecasts_5Min_DK1_Offshore_2024.csv", DataFrame)

timestamp_col = :Minutes5DK
day_ahead_col = :ForecastDayAhead 

# Parse timestamp -> DateTime (the format string matches "dd-mm-yyyy HH:MM:SS")
Wind_DK1_2024.:ts = DateTime.(Wind_DK1_2024[!, timestamp_col], dateformat"dd-mm-yyyy HH:MM:SS")

# If you already have DK time, keep using it; else convert/rename as you like.
select!(Wind_DK1_2024, Not(timestamp_col))  # keep parsed :ts and other columns

# --- Make a complete 5-min calendar for 2024 ---------------------------------
full_range = DateTime(2024,1,1,0,0,0):Minute(5):DateTime(2024,12,31,23,55,0)
full_calendar = DataFrame(ts = collect(full_range))

# Outer-join so we can see misses; sort for safety
global df = outerjoin(full_calendar, Wind_DK1_2024, on = :ts, makeunique=true)
sort!(df, :ts)

# Convenience columns
df.date = Date.(df.ts)
df.tod  = Time.(df.ts)

# --- Helpers ------------------------------------------------------------------
# Identify dates that are "complete" for a given column (all 288 intervals present & non-missing)
function complete_days(df::DataFrame, col::Symbol)
    days = Date[]
    for sub in groupby(df, :date)
        if nrow(sub) == 288 && all(!ismissing, sub[!, col])
            push!(days, sub.date[1])
        end
    end
    return days
end
function random_complete_day(df::DataFrame, col::Symbol; seed::Int=0)
    seed != 0 && Random.seed!(seed)
    days = complete_days(df, col)
    isempty(days) && error("No complete days available for column $(col).")
    return rand(days)
end
d0 = random_complete_day(df,day_ahead_col, seed=123)
println("Donor date: $d0")

# --- 1) Fill completely missing days -----------------------------------------
# missing whole days: 2024-04-13, 2024-04-14, 2024-04-15, 2024-11-17, 2024-12-31
missing_whole_days = [Date(2024,4,13), Date(2024,4,14),Date(2024,4,15), Date(2024,11,17),Date(2024,12,31)]

# Choose which columns to fill when an entire day is gone.
numeric_cols = [Symbol(c) for c in names(df) if c ∉ ["ts", "date", "tod"] && eltype(df[!, c]) <: Union{Missing, Number}]

# Fill a whole missing day for a list of columns by copying a random complete donor day
function fill_whole_day_from_random!(df::DataFrame; target_date::Date, cols::Vector{Symbol}, donor_date::Date)

    d0 = donor_date
    donor = df[df.date .== d0, [:tod; cols]]

    for c in cols
        lut = Dict(donor.tod .=> donor[!, c])
        mask = df.date .== target_date
        df[mask, c] = getindex.(Ref(lut), df[mask, :tod])
    end
    return df
end

# Fill a partial-day gap in one column by copying values (time-of-day aligned) from a random complete donor day
function fill_partial_day_from_random!(df::DataFrame; target_date::Date, col::Symbol, time_start::Time, time_end::Time, donor_date::Date)

    d0 = donor_date
    donor = df[df.date .== d0, [:tod, col]]
    lut = Dict(donor.tod .=> donor[!, col])

    mask = (df.date .== target_date) .& (df.tod .>= time_start) .& (df.tod .<= time_end) .& ismissing.(df[!, col])
    df[mask, col] = getindex.(Ref(lut), df[mask, :tod])
    return df
end

for d in missing_whole_days
    fill_whole_day_from_random!(df; target_date=d, cols=numeric_cols, donor_date = d0)
end

# --- 2) Fill the partial hole in the DayAhead column on 2024-04-15 08:05–23:55 ---
df = fill_partial_day_from_random!(df;
    target_date = Date(2024,4,15),
    col = day_ahead_col,
    time_start = Time(8,5),
    time_end   = Time(23,55),
    donor_date = d0
)


# --- Save result ---------------------------------------------------------------
clean = select(df, Not([:date, :tod]))


# last Sunday of a month (works with Base.Dates only)
function last_sunday_in_month(year::Int, month::Int)
    d = Date(year, month, Dates.daysinmonth(Date(year, month, 1)))
    while dayofweek(d) != Dates.Sunday
        d -= Day(1)
    end
    return d
end

function without_spring_forward_gap(df::DataFrame; local_ts::Symbol, year::Int=2024)
    gap_date = last_sunday_in_month(year, 3)
    local_vec = df[!, local_ts]
    dates = Date.(local_vec)
    tod   = Time.(local_vec)
    mask  = (dates .== gap_date) .& (Time(2,0) .<= tod .<= Time(2,55))
    return df[.!mask, :]
end

df = without_spring_forward_gap(df; local_ts=:ts, year=2024)

# --- (Optional) sanity checks --------------------------------------------------
# Verify there are no missing rows in the year timeline:
@assert nrow(df) == length(full_range)
#nrow(df)-length(full_range)

one_year_wind = df.ForecastDayAhead

# Check remaining missings in important columns
for c in numeric_cols
    nmiss = count(ismissing, df[!, c])
    @info "Remaining missings in $(c): $(nmiss)"
end