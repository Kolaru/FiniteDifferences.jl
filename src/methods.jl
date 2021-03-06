export FiniteDifferenceMethod, fdm, backward_fdm, forward_fdm, central_fdm, extrapolate_fdm

"""
    estimate_magitude(f, x::T) where T<:AbstractFloat

Estimate the magnitude of `f` in a neighbourhood of `x`, assuming that the outputs of `f`
have a "typical" order of magnitude. The result should be interpreted as a very rough
estimate. This function deals with the case that `f(x) = 0`.
"""
function estimate_magitude(f, x::T) where T<:AbstractFloat
    M = float(maximum(abs, f(x)))
    M > 0 && (return M)
    # Ouch, `f(x) = 0`. But it may not be zero around `x`. We conclude that `x` is likely a
    # pathological input for `f`. Perturb `x`. Assume that the pertubed value for `x` is
    # highly unlikely also a pathological value for `f`.
    Δ = convert(T, 0.1) * max(abs(x), one(x))
    return float(maximum(abs, f(x + Δ)))
end

"""
    estimate_roundoff_error(f, x::T) where T<:AbstractFloat

Estimate the round-off error of `f(x)`. This function deals with the case that `f(x) = 0`.
"""
function estimate_roundoff_error(f, x::T) where T<:AbstractFloat
    # Estimate the round-off error. It can happen that the function is zero around `x`, in
    # which case we cannot take `eps(f(x))`. Therefore, we assume a lower bound that is
    # equal to `eps(T) / 1000`, which gives `f` four orders of magnitude wiggle room.
    return max(eps(estimate_magitude(f, x)), eps(T) / 1000)
end

"""
    FiniteDifferences.DEFAULT_CONDITION

The default [condition number](https://en.wikipedia.org/wiki/Condition_number) used when
computing bounds. It provides amplification of the ∞-norm when passed to the function's
derivatives.
"""
const DEFAULT_CONDITION = 100

"""
    FiniteDifferenceMethod{G<:AbstractVector, C<:AbstractVector, E<:Function}

A finite difference method.

# Fields
- `grid::G`: Multiples of the step size that the function will be evaluated at.
- `q::Int`: Order of derivative to estimate.
- `coefs::C`: Coefficients corresponding to the grid functions that the function evaluations
    will be weighted by.
- `bound_estimator::Function`: A function that takes in the function and the evaluation
    point and returns a bound on the magnitude of the `length(grid)`th derivative.
"""
struct FiniteDifferenceMethod{G<:AbstractVector, C<:AbstractVector, E<:Function}
    grid::G
    q::Int
    coefs::C
    bound_estimator::E
end

"""
    FiniteDifferenceMethod(
        grid::AbstractVector,
        q::Int;
        condition::Real=DEFAULT_CONDITION
    )

Construct a finite difference method.

# Arguments
- `grid::Abstract`: The grid. See [`FiniteDifferenceMethod`](@ref).
- `q::Int`: Order of the derivative to estimate.
- `condition::Real`: Condition number. See [`DEFAULT_CONDITION`](@ref).

# Returns
- `FiniteDifferenceMethod`: Specified finite difference method.
"""
function FiniteDifferenceMethod(
    grid::AbstractVector,
    q::Int;
    condition::Real=DEFAULT_CONDITION
)
    p = length(grid)
    _check_p_q(p, q)
    return FiniteDifferenceMethod(
        grid,
        q,
        _coefs(grid, q),
        _make_default_bound_estimator(condition=condition)
    )
end

"""
    (m::FiniteDifferenceMethod)(
        f::Function,
        x::T;
        factor::Real=1,
        max_step::Real=0.1 * max(abs(x), one(x))
    ) where T<:AbstractFloat

Estimate the derivative of `f` at `x` using the finite differencing method `m` and an
automatically determined step size.

# Arguments
- `f::Function`: Function to estimate derivative of.
- `x::T`: Input to estimate derivative at.

# Keywords
- `factor::Real=1`: Factor to amplify the estimated round-off error by. This can be used
    to force a more conservative step size.
- `max_step::Real=0.1 * max(abs(x), one(x))`: Maximum step size.

# Returns
- Estimate of the derivative.

# Examples

```julia-repl
julia> fdm = central_fdm(5, 1)
FiniteDifferenceMethod:
  order of method:       5
  order of derivative:   1
  grid:                  [-2, -1, 0, 1, 2]
  coefficients:          [0.08333333333333333, -0.6666666666666666, 0.0, 0.6666666666666666, -0.08333333333333333]

julia> fdm(sin, 1)
0.5403023058681155

julia> fdm(sin, 1) - cos(1)  # Check the error.
-2.4313884239290928e-14

julia> FiniteDifferences.estimate_step(fdm, sin, 1.0)  # Computes step size and estimates the error.
(0.0010632902144695163, 1.9577610541734626e-13)
```
"""
@inline function (m::FiniteDifferenceMethod)(f::Function, x::Real; kw_args...)
    # Assume that converting to float is desired.
    return _call_method(m, f, float(x); kw_args...)
end
@inline function _call_method(
    m::FiniteDifferenceMethod,
    f::Function,
    x::T;
    factor::Real=1,
    max_step::Real=0.1 * max(abs(x), one(x))
) where T<:AbstractFloat
    # The automatic step size calculation fails if `m.q == 0`, so handle that edge case.
    iszero(m.q) && return f(x)
    h, _ = estimate_step(m, f, x, factor=factor, max_step=max_step)
    return _eval_method(m, f, x, h)
end

"""
    (m::FiniteDifferenceMethod)(f::Function, x::T, h::Real) where T<:AbstractFloat

Estimate the derivative of `f` at `x` using the finite differencing method `m` and a given
step size.

# Arguments
- `f::Function`: Function to estimate derivative of.
- `x::T`: Input to estimate derivative at.
- `h::Real`: Step size.

# Returns
- Estimate of the derivative.

# Examples

```julia-repl
julia> fdm = central_fdm(5, 1)
FiniteDifferenceMethod:
  order of method:       5
  order of derivative:   1
  grid:                  [-2, -1, 0, 1, 2]
  coefficients:          [0.08333333333333333, -0.6666666666666666, 0.0, 0.6666666666666666, -0.08333333333333333]

julia> fdm(sin, 1, 1e-3)
0.5403023058679624

julia> fdm(sin, 1, 1e-3) - cos(1)  # Check the error.
-1.7741363933510002e-13
```
"""
@inline function (m::FiniteDifferenceMethod)(f::Function, x::Real, h::Real)
    # Assume that converting to float is desired.
    return _eval_method(m, f, float(x), h)
end
@inline function _eval_method(
    m::FiniteDifferenceMethod,
    f::Function,
    x::T,
    h::Real
) where T<:AbstractFloat
    return sum(
        i -> convert(T, m.coefs[i]) * f(T(x + h * m.grid[i])),
        eachindex(m.grid)
    ) / h^m.q
end

# Check the method and derivative orders for consistency.
function _check_p_q(p::Integer, q::Integer)
    q >= 0 || throw(DomainError(q, "order of derivative (`q`) must be non-negative"))
    q < p || throw(DomainError(
        (q, p),
        "order of the method (q) must be strictly greater than that of the derivative (p)",
    ))
    # Check whether the method can be computed. We require the factorial of the method order
    # to be computable with regular `Int`s, but `factorial` will after 20, so 20 is the
    # largest we can allow.
    p > 20 && throw(DomainError(p, "order of the method (`p`) is too large to be computed"))
    return
end

const _COEFFS_CACHE = Dict{Tuple{AbstractVector{<:Real}, Integer}, Vector{Float64}}()

# Compute coefficients for the method and cache the result.
function _coefs(grid::AbstractVector{<:Real}, q::Integer)
    return get!(_COEFFS_CACHE, (grid, q)) do
        p = length(grid)
        # For high precision on the `\`, we use `Rational`, and to prevent overflows we use
        # `Int128`. At the end we go to `Float64` for fast floating point math, rather than
        # rational math.
        C = [Rational{Int128}(g^i) for i in 0:(p - 1), g in grid]
        x = zeros(Rational{Int128}, p)
        x[q + 1] = factorial(q)
        return Float64.(C \ x)
    end
end

# Estimate the bound on the derivative by amplifying the ∞-norm.
function _make_default_bound_estimator(; condition::Real=DEFAULT_CONDITION)
    default_bound_estimator(f, x) = condition * estimate_magitude(f, x)
    return default_bound_estimator
end

function Base.show(io::IO, m::MIME"text/plain", x::FiniteDifferenceMethod)
    @printf io "FiniteDifferenceMethod:\n"
    @printf io "  order of method:       %d\n" length(x.grid)
    @printf io "  order of derivative:   %d\n" x.q
    @printf io "  grid:                  %s\n" x.grid
    @printf io "  coefficients:          %s\n" x.coefs
end

"""
    function estimate_step(
        m::FiniteDifferenceMethod,
        f::Function,
        x::T;
        factor::Real=1,
        max_step::Real=0.1 * max(abs(x), one(x))
    ) where T<:AbstractFloat

Estimate the step size for a finite difference method `m`. Also estimates the error of the
estimate of the derivative.

# Arguments
- `m::FiniteDifferenceMethod`: Finite difference method to estimate the step size for.
- `f::Function`: Function to evaluate the derivative of.
- `x::T`: Point to estimate the derivative at.

# Keywords
- `factor::Real=1`. Factor to amplify the estimated round-off error by. This can be used
    to force a more conservative step size.
- `max_step::Real=0.1 * max(abs(x), one(x))`: Maximum step size.

# Returns
- `Tuple{T, <:AbstractFloat}`: Estimated step size and an estimate of the error of the
    finite difference estimate.
"""
function estimate_step(
    m::FiniteDifferenceMethod,
    f::Function,
    x::T;
    factor::Real=1,
    max_step::Real=0.1 * max(abs(x), one(x))
) where T<:AbstractFloat
    p = length(m.coefs)
    q = m.q

    # Estimate the round-off error.
    ε = estimate_roundoff_error(f, x) * factor

    # Estimate the bound on the derivatives.
    M = m.bound_estimator(f, x)

    # Set the step size by minimising an upper bound on the error of the estimate.
    C₁ = ε * sum(abs, m.coefs)
    C₂ = M * sum(n -> abs(m.coefs[n] * m.grid[n]^p), eachindex(m.coefs)) / factorial(p)
    # Type inference fails on this, so we annotate it, which gives big performance benefits.
    h::T = convert(T, min((q / (p - q) * (C₁ / C₂))^(1 / p), max_step))

    # Estimate the accuracy of the method.
    accuracy = h^(-q) * C₁ + h^(p - q) * C₂

    return h, accuracy
end

for direction in [:forward, :central, :backward]
    fdm_fun = Symbol(direction, "_fdm")
    grid_fun = Symbol("_", direction, "_grid")
    @eval begin function $fdm_fun(
            p::Int,
            q::Int;
            adapt::Int=1,
            condition::Real=DEFAULT_CONDITION,
            geom::Bool=false
        )
            _check_p_q(p, q)
            grid = $grid_fun(p)
            geom && (grid = _exponentiate_grid(grid))
            coefs = _coefs(grid, q)
            return FiniteDifferenceMethod(
                grid,
                q,
                coefs,
                _make_adaptive_bound_estimator($fdm_fun, p, q, adapt, condition, geom=geom),
            )
        end

        @doc """
    $($(Meta.quot(fdm_fun)))(
        p::Int,
        q::Int;
        adapt::Int=1,
        condition::Real=DEFAULT_CONDITION,
        geom::Bool=false
    )

Contruct a finite difference method at a $($(Meta.quot(direction))) grid of `p` linearly
spaced points.

# Arguments
- `p::Int`: Number of grid points.
- `q::Int`: Order of the derivative to estimate.

# Keywords
- `adapt::Int=1`: Use another finite difference method to estimate the magnitude of the
    `p`th order derivative, which is important for the step size computation. Recurse
    this procedure `adapt` times.
- `condition::Real`: Condition number. See [`DEFAULT_CONDITION`](@ref).
- `geom::Bool`: Use geometrically spaced points instead of linearly spaced points.

# Returns
- `FiniteDifferenceMethod`: The specified finite difference method.
        """ $fdm_fun
    end
end

function _make_adaptive_bound_estimator(
    constructor::Function,
    p::Int,
    q::Int,
    adapt::Int,
    condition::Int;
    kw_args...
)
    if adapt >= 1
        estimate_derivative = constructor(
            p + 1, p, adapt=adapt - 1, condition=condition; kw_args...
        )
        return (f, x) -> estimate_magitude(x′ -> estimate_derivative(f, x′), x)
    else
        return _make_default_bound_estimator(condition=condition)
    end
end

_forward_grid(p::Int) = collect(0:(p - 1))

_backward_grid(p::Int) = collect((1 - p):0)

function _central_grid(p::Int)
    if isodd(p)
        return collect(div(1 - p, 2):div(p - 1, 2))
    else
        return vcat(div(-p, 2):-1, 1:div(p, 2))
    end
end

_exponentiate_grid(grid::Vector, base::Int=3) = sign.(grid) .* base .^ abs.(grid) ./ base

function _is_symmetric(vec::Vector; centre_zero::Bool=false, negate_half::Bool=false)
    half_sign = negate_half ? -1 : 1
    if isodd(length(vec))
        centre_zero && vec[end ÷ 2 + 1] != 0 && return false
        return vec[1:end ÷ 2] == half_sign .* reverse(vec[(end ÷ 2 + 2):end])
    else
        return vec[1:end ÷ 2] == half_sign .* reverse(vec[(end ÷ 2 + 1):end])
    end
end

function _is_symmetric(m::FiniteDifferenceMethod)
    grid_symmetric = _is_symmetric(m.grid, centre_zero=true, negate_half=true)
    coefs_symmetric =_is_symmetric(m.coefs, negate_half=true)
    return grid_symmetric && coefs_symmetric
end

"""
    extrapolate_fdm(
        m::FiniteDifferenceMethod,
        f::Function,
        x::T,
        h::Real=0.1 * max(abs(x), one(x));
        power=nothing,
        breaktol=Inf,
        kw_args...
    ) where T<:AbstractFloat

Use Richardson extrapolation to refine a finite difference method.

Takes further in keyword arguments for `Richardson.extrapolate`. This method
automatically sets `power = 2` if `m` is symmetric and `power = 1`. Moreover, it defaults
`breaktol = Inf`.

# Arguments
- `m::FiniteDifferenceMethod`: Finite difference method to estimate the step size for.
- `f::Function`: Function to evaluate the derivative of.
- `x::T`: Point to estimate the derivative at.
- `h::Real=0.1 * max(abs(x), one(x))`: Initial step size.

# Returns
- `Tuple{<:AbstractFloat, <:AbstractFloat}`: Estimate of the derivative and error.
"""
function extrapolate_fdm(
    m::FiniteDifferenceMethod,
    f::Function,
    x::T,
    h::Real=0.1 * max(abs(x), one(x));
    power::Int=1,
    breaktol::Real=Inf,
    kw_args...
) where T<:AbstractFloat
    (power == 1 && _is_symmetric(m)) && (power = 2)
    return extrapolate(h -> m(f, x, h), h; power=power, breaktol=breaktol, kw_args...)
end
