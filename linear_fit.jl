using Plots
using JuMP, Ipopt, Statistics
using Printf

pgfplotsx()

# Data
x = [60.0, 70.04608294930875, 80.0, 90.01536098310292, 100.0]
y = [1.3274358974358975, 1.5607692307692307, 1.7994871794871794,
     2.068717948717949, 2.327179487179487]

function fit_linear_model(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    @assert length(x) == length(y) "x and y must be the same length"

    model = Model(Ipopt.Optimizer)

    @variable(model, a)
    @variable(model, b)

    @objective(model, Min, sum((a * x[i] + b - y[i])^2 for i in 1:length(x)))

    optimize!(model)

    a_opt = value(a)
    b_opt = value(b)

    return a_opt, b_opt
end

a, b = fit_linear_model(x,y)

fit_x = 60:5:100
fit_y = a.*fit_x .+b

p = plot(x, y, seriestype=:scatter, label="Data", xlabel="Load (%)", ylabel="Power (kW)",
     title="Power vs Load (Linear Fit)")
plot!(fit_x, fit_y, label="Linear fit", linewidth=2)

savefig(p, raw"C:\Users\lisadan\OneDrive - Danmarks Tekniske Universitet\12_Research\05_AEM_electrolyzer\03_code\AEM-Scheduling\plots\production_curve_fit.tex")

function regression_metrics(P, L, a, b)
    # Compute residuals
    residuals = [L[i] - (a  * P[i]+ b) for i in 1:length(L)]
    
    # Sum of squares
    ssr = sum(residuals .^ 2)                    # Sum of squared residuals
    sst = sum((L .- mean(L)) .^ 2)               # Total sum of squares
    
    # R² and Max Error
    r2 = 1 - ssr / sst
    max_err = maximum(abs.(residuals))
    
    return r2, max_err, residuals
end

m1 = regression_metrics(x, y, a, b)
# Pretty printer for one segment
function print_regression_report(label, P, L, a, b)
    r2, max_err, resid = regression_metrics(P, L, a, b)
    n   = length(L)
    rss = sum(resid .^ 2)
    rmse = sqrt(rss / n)
    mae  = mean(abs.(resid))
    @printf("%-12s | a = %.16f  b = %.16f | R^2 = %.5f | RMSE = %7.3f | MAE = %7.3f | MaxErr = %7.3f\n",
            label, a, b, r2, rmse, mae, max_err)
end

println("\n=== Linear fit regression metrics ===")
print_regression_report("AEM", x, y, a, b)