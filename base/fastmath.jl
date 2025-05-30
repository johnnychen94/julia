# This file is a part of Julia. License is MIT: https://julialang.org/license

# Support for @fastmath

# This module provides versions of math functions that may violate
# strict IEEE semantics.

# This allows the following transformations. For more information see
# https://llvm.org/docs/LangRef.html#fast-math-flags:
# nnan: No NaNs - Allow optimizations to assume the arguments and
#       result are not NaN. Such optimizations are required to retain
#       defined behavior over NaNs, but the value of the result is
#       undefined.
# ninf: No Infs - Allow optimizations to assume the arguments and
#       result are not +/-Inf. Such optimizations are required to
#       retain defined behavior over +/-Inf, but the value of the
#       result is undefined.
# nsz:  No Signed Zeros - Allow optimizations to treat the sign of a
#       zero argument or result as insignificant.
# arcp: Allow Reciprocal - Allow optimizations to use the reciprocal
#       of an argument rather than perform division.
# fast: Fast - Allow algebraically equivalent transformations that may
#       dramatically change results in floating point (e.g.
#       reassociate). This flag implies all the others.

module FastMath

export @fastmath

import Core.Intrinsics: sqrt_llvm_fast, neg_float_fast,
    add_float_fast, sub_float_fast, mul_float_fast, div_float_fast, min_float_fast, max_float_fast,
    eq_float_fast, ne_float_fast, lt_float_fast, le_float_fast
import Base: afoldl

const fast_op =
    Dict(# basic arithmetic
         :+ => :add_fast,
         :- => :sub_fast,
         :* => :mul_fast,
         :/ => :div_fast,
         :(==) => :eq_fast,
         :!= => :ne_fast,
         :< => :lt_fast,
         :<= => :le_fast,
         :> => :gt_fast,
         :>= => :ge_fast,
         :abs => :abs_fast,
         :abs2 => :abs2_fast,
         :cmp => :cmp_fast,
         :conj => :conj_fast,
         :inv => :inv_fast,
         :rem => :rem_fast,
         :sign => :sign_fast,
         :isfinite => :isfinite_fast,
         :isinf => :isinf_fast,
         :isnan => :isnan_fast,
         :issubnormal => :issubnormal_fast,
         # math functions
         :^ => :pow_fast,
         :acos => :acos_fast,
         :acosh => :acosh_fast,
         :angle => :angle_fast,
         :asin => :asin_fast,
         :asinh => :asinh_fast,
         :atan => :atan_fast,
         :atanh => :atanh_fast,
         :cbrt => :cbrt_fast,
         :cis => :cis_fast,
         :cos => :cos_fast,
         :cosh => :cosh_fast,
         :exp10 => :exp10_fast,
         :exp2 => :exp2_fast,
         :exp => :exp_fast,
         :expm1 => :expm1_fast,
         :hypot => :hypot_fast,
         :log10 => :log10_fast,
         :log1p => :log1p_fast,
         :log2 => :log2_fast,
         :log => :log_fast,
         :max => :max_fast,
         :min => :min_fast,
         :minmax => :minmax_fast,
         :sin => :sin_fast,
         :sincos => :sincos_fast,
         :sinh => :sinh_fast,
         :sqrt => :sqrt_fast,
         :tan => :tan_fast,
         :tanh => :tanh_fast,
         # reductions
         :maximum => :maximum_fast,
         :minimum => :minimum_fast,
         :maximum! => :maximum!_fast,
         :minimum! => :minimum!_fast)

const rewrite_op =
    Dict(:+= => :+,
         :-= => :-,
         :*= => :*,
         :/= => :/,
         :^= => :^)

function make_fastmath(expr::Expr)
    if expr.head === :quote
        return expr
    elseif expr.head === :call && expr.args[1] === :^
        ea = expr.args
        if length(ea) >= 3 && isa(ea[3], Int)
            # mimic Julia's literal_pow lowering of literal integer powers
            return Expr(:call, :(Base.FastMath.pow_fast), make_fastmath(ea[2]), Val(ea[3]))
        end
    end
    op = get(rewrite_op, expr.head, :nothing)
    if op !== :nothing
        var = expr.args[1]
        rhs = expr.args[2]
        if isa(var, Symbol)
            # simple assignment
            expr = :($var = $op($var, $rhs))
        end
        # It is hard to optimize array[i += 1] += 1
        # and array[end] += 1 without bugs. (#47241)
        # We settle for not optimizing the op= call.
    end
    Base.exprarray(make_fastmath(expr.head), Base.mapany(make_fastmath, expr.args))
end
function make_fastmath(symb::Symbol)
    fast_symb = get(fast_op, symb, :nothing)
    if fast_symb === :nothing
        return symb
    end
    :(Base.FastMath.$fast_symb)
end
make_fastmath(expr) = expr

"""
    @fastmath expr

Execute a transformed version of the expression, which calls functions that
may violate strict IEEE semantics. This allows the fastest possible operation,
but results are undefined -- be careful when doing this, as it may change numerical
results.

This sets the [LLVM Fast-Math flags](https://llvm.org/docs/LangRef.html#fast-math-flags),
and corresponds to the `-ffast-math` option in clang. See [the notes on performance
annotations](@ref man-performance-annotations) for more details.

# Examples
```jldoctest
julia> @fastmath 1+2
3

julia> @fastmath(sin(3))
0.1411200080598672
```
"""
macro fastmath(expr)
    make_fastmath(esc(expr))
end


# Basic arithmetic

const FloatTypes = Union{Float16,Float32,Float64}

sub_fast(x::FloatTypes) = neg_float_fast(x)

add_fast(x::T, y::T) where {T<:FloatTypes} = add_float_fast(x, y)
sub_fast(x::T, y::T) where {T<:FloatTypes} = sub_float_fast(x, y)
mul_fast(x::T, y::T) where {T<:FloatTypes} = mul_float_fast(x, y)
div_fast(x::T, y::T) where {T<:FloatTypes} = div_float_fast(x, y)
max_fast(x::T, y::T) where {T<:FloatTypes} = max_float_fast(x, y)
min_fast(x::T, y::T) where {T<:FloatTypes} = min_float_fast(x, y)
minmax_fast(x::T, y::T) where {T<:FloatTypes} = (min_fast(x, y), max_fast(x, y))

@fastmath begin
    cmp_fast(x::T, y::T) where {T<:FloatTypes} = ifelse(x==y, 0, ifelse(x<y, -1, +1))
    log_fast(b::T, x::T) where {T<:FloatTypes} = log_fast(x)/log_fast(b)
end

eq_fast(x::T, y::T) where {T<:FloatTypes} = eq_float_fast(x, y)
ne_fast(x::T, y::T) where {T<:FloatTypes} = ne_float_fast(x, y)
lt_fast(x::T, y::T) where {T<:FloatTypes} = lt_float_fast(x, y)
le_fast(x::T, y::T) where {T<:FloatTypes} = le_float_fast(x, y)
gt_fast(x, y) = lt_fast(y, x)
ge_fast(x, y) = le_fast(y, x)

isinf_fast(x) = false
isfinite_fast(x) = true
isnan_fast(x) = false
issubnormal_fast(x) = false

# complex numbers

ComplexTypes = Union{ComplexF32, ComplexF64}

@fastmath begin
    abs_fast(x::ComplexTypes) = hypot(real(x), imag(x))
    abs2_fast(x::ComplexTypes) = real(x)*real(x) + imag(x)*imag(x)
    conj_fast(x::T) where {T<:ComplexTypes} = T(real(x), -imag(x))
    inv_fast(x::ComplexTypes) = conj(x) / abs2(x)
    sign_fast(x::ComplexTypes) = x == 0 ? float(zero(x)) : x/abs(x)

    add_fast(x::T, y::T) where {T<:ComplexTypes} =
        T(real(x)+real(y), imag(x)+imag(y))
    add_fast(x::Complex{T}, b::T) where {T<:FloatTypes} =
        Complex{T}(real(x)+b, imag(x))
    add_fast(a::T, y::Complex{T}) where {T<:FloatTypes} =
        Complex{T}(a+real(y), imag(y))

    sub_fast(x::T, y::T) where {T<:ComplexTypes} =
        T(real(x)-real(y), imag(x)-imag(y))
    sub_fast(x::Complex{T}, b::T) where {T<:FloatTypes} =
        Complex{T}(real(x)-b, imag(x))
    sub_fast(a::T, y::Complex{T}) where {T<:FloatTypes} =
        Complex{T}(a-real(y), -imag(y))

    mul_fast(x::T, y::T) where {T<:ComplexTypes} =
        T(real(x)*real(y) - imag(x)*imag(y),
          real(x)*imag(y) + imag(x)*real(y))
    mul_fast(x::Complex{T}, b::T) where {T<:FloatTypes} =
        Complex{T}(real(x)*b, imag(x)*b)
    mul_fast(a::T, y::Complex{T}) where {T<:FloatTypes} =
        Complex{T}(a*real(y), a*imag(y))

    @inline div_fast(x::T, y::T) where {T<:ComplexTypes} =
        T(real(x)*real(y) + imag(x)*imag(y),
          imag(x)*real(y) - real(x)*imag(y)) / abs2(y)
    div_fast(x::Complex{T}, b::T) where {T<:FloatTypes} =
        Complex{T}(real(x)/b, imag(x)/b)
    div_fast(a::T, y::Complex{T}) where {T<:FloatTypes} =
        Complex{T}(a*real(y), -a*imag(y)) / abs2(y)

    eq_fast(x::T, y::T) where {T<:ComplexTypes} =
        (real(x)==real(y)) & (imag(x)==imag(y))
    eq_fast(x::Complex{T}, b::T) where {T<:FloatTypes} =
        (real(x)==b) & (imag(x)==T(0))
    eq_fast(a::T, y::Complex{T}) where {T<:FloatTypes} =
        (a==real(y)) & (T(0)==imag(y))

    ne_fast(x::T, y::T) where {T<:ComplexTypes} = !(x==y)

end

# fall-back implementations and type promotion

for op in (:abs, :abs2, :conj, :inv, :sign)
    op_fast = fast_op[op]
    @eval begin
        # fall-back implementation for non-numeric types
        $op_fast(xs...) = $op(xs...)
    end
end

for op in (:-, :/, :(==), :!=, :<, :<=, :cmp, :rem, :minmax)
    op_fast = fast_op[op]
    @eval begin
        # fall-back implementation for non-numeric types
        $op_fast(xs...) = $op(xs...)
        # type promotion
        $op_fast(x::Number, y::Number, zs::Number...) =
            $op_fast(promote(x,y,zs...)...)
        # fall-back implementation that applies after promotion
        $op_fast(x::T,ys::T...) where {T<:Number} = $op(x,ys...)
    end
end

for op in (:+, :*, :min, :max)
    op_fast = fast_op[op]
    @eval begin
        $op_fast(x) = $op(x)
        # fall-back implementation for non-numeric types
        $op_fast(x, y) = $op(x, y)
        # type promotion
        $op_fast(x::Number, y::Number) =
            $op_fast(promote(x,y)...)
        # fall-back implementation that applies after promotion
        $op_fast(x::T,y::T) where {T<:Number} = $op(x,y)
        # note: these definitions must not cause a dispatch loop when +(a,b) is
        # not defined, and must only try to call 2-argument definitions, so
        # that defining +(a,b) is sufficient for full functionality.
        ($op_fast)(a, b, c, xs...) = (@inline; afoldl($op_fast, ($op_fast)(($op_fast)(a,b),c), xs...))
        # a further concern is that it's easy for a type like (Int,Int...)
        # to match many definitions, so we need to keep the number of
        # definitions down to avoid losing type information.
        # type promotion
        $op_fast(a::Number, b::Number, c::Number, xs::Number...) =
            $op_fast(promote(a,b,c,xs...)...)
        # fall-back implementation that applies after promotion
        $op_fast(a::T, b::T, c::T, xs::T...) where {T<:Number} = (@inline; afoldl($op_fast, ($op_fast)(($op_fast)(a,b),c), xs...))
    end
end

# Math functions
exp2_fast(x::Union{Float32,Float64})  = Base.Math.exp2_fast(x)
exp_fast(x::Union{Float32,Float64})   = Base.Math.exp_fast(x)
exp10_fast(x::Union{Float32,Float64}) = Base.Math.exp10_fast(x)

# builtins

function pow_fast(x::Float64, y::Integer)
    z = y % Int32
    z == y ? pow_fast(x, z) : x^y
end
pow_fast(x::Float32, y::Integer) = x^y
pow_fast(x::Float64, y::Int32) = ccall("llvm.powi.f64.i32", llvmcall, Float64, (Float64, Int32), x, y)
pow_fast(x::FloatTypes, ::Val{p}) where {p} = pow_fast(x, p) # inlines already via llvm.powi
@inline pow_fast(x, v::Val) = Base.literal_pow(^, x, v)

sqrt_fast(x::FloatTypes) = sqrt_llvm_fast(x)
sincos_fast(v::FloatTypes) = sincos(v)

@inline function sincos_fast(v::Float16)
    s, c = sincos_fast(Float32(v))
    return Float16(s), Float16(c)
end
sincos_fast(v::AbstractFloat) = (sin_fast(v), cos_fast(v))
sincos_fast(v::Real) = sincos_fast(float(v)::AbstractFloat)
sincos_fast(v) = (sin_fast(v), cos_fast(v))


function rem_fast(x::T, y::T) where {T<:FloatTypes}
    return @fastmath copysign(Base.rem_internal(abs(x), abs(y)), x)
end

@fastmath begin
    hypot_fast(x::T, y::T) where {T<:FloatTypes} = sqrt(x*x + y*y)

    # complex numbers

    function cis_fast(x::T) where {T<:FloatTypes}
        s, c = sincos_fast(x)
        Complex{T}(c, s)
    end

    # See <https://en.cppreference.com/w/cpp/numeric/complex>
    pow_fast(x::T, y::T) where {T<:ComplexTypes} = exp(y*log(x))
    pow_fast(x::T, y::Complex{T}) where {T<:FloatTypes} = exp(y*log(x))
    pow_fast(x::Complex{T}, y::T) where {T<:FloatTypes} = exp(y*log(x))
    acos_fast(x::T) where {T<:ComplexTypes} =
        convert(T,π)/2 + im*log(im*x + sqrt(1-x*x))
    acosh_fast(x::ComplexTypes) = log(x + sqrt(x+1) * sqrt(x-1))
    angle_fast(x::ComplexTypes) = atan(imag(x), real(x))
    asin_fast(x::ComplexTypes) = -im*asinh(im*x)
    asinh_fast(x::ComplexTypes) = log(x + sqrt(1+x*x))
    atan_fast(x::ComplexTypes) = -im*atanh(im*x)
    atanh_fast(x::T) where {T<:ComplexTypes} = convert(T,1)/2*(log(1+x) - log(1-x))
    cis_fast(x::ComplexTypes) = exp(-imag(x)) * cis(real(x))
    cos_fast(x::ComplexTypes) = cosh(im*x)
    cosh_fast(x::T) where {T<:ComplexTypes} = convert(T,1)/2*(exp(x) + exp(-x))
    exp10_fast(x::T) where {T<:ComplexTypes} =
        exp10(real(x)) * cis(imag(x)*log(convert(T,10)))
    exp2_fast(x::T) where {T<:ComplexTypes} =
        exp2(real(x)) * cis(imag(x)*log(convert(T,2)))
    exp_fast(x::ComplexTypes) = exp(real(x)) * cis(imag(x))
    expm1_fast(x::ComplexTypes) = exp(x)-1
    log10_fast(x::T) where {T<:ComplexTypes} = log(x) / log(convert(T,10))
    log1p_fast(x::ComplexTypes) = log(1+x)
    log2_fast(x::T) where {T<:ComplexTypes} = log(x) / log(convert(T,2))
    log_fast(x::T) where {T<:ComplexTypes} = T(log(abs2(x))/2, angle(x))
    log_fast(b::T, x::T) where {T<:ComplexTypes} = T(log(x)/log(b))
    sin_fast(x::ComplexTypes) = -im*sinh(im*x)
    sinh_fast(x::T) where {T<:ComplexTypes} = convert(T,1)/2*(exp(x) - exp(-x))
    sqrt_fast(x::ComplexTypes) = sqrt(abs(x)) * cis(angle(x)/2)
    tan_fast(x::ComplexTypes) = -im*tanh(im*x)
    tanh_fast(x::ComplexTypes) = (a=exp(x); b=exp(-x); (a-b)/(a+b))
end

# fall-back implementations and type promotion

for f in (:acos, :acosh, :angle, :asin, :asinh, :atan, :atanh, :cbrt,
          :cis, :cos, :cosh, :exp10, :exp2, :exp, :expm1,
          :log10, :log1p, :log2, :log, :sin, :sinh, :sqrt, :tan,
          :tanh)
    f_fast = fast_op[f]
    @eval begin
        $f_fast(x) = $f(x)
    end
end

for f in (:^, :atan, :hypot, :log)
    f_fast = fast_op[f]
    @eval begin
        # fall-back implementation for non-numeric types
        $f_fast(x, y) = $f(x, y)
        # type promotion
        $f_fast(x::Number, y::Number) = $f_fast(promote(x, y)...)
        # fall-back implementation that applies after promotion
        $f_fast(x::T, y::T) where {T<:Number} = $f(x, y)
    end
    # Issue 53886 - avoid promotion of Int128 etc to be consistent with non-fastmath
    if f === :^
        @eval $f_fast(x::Number, y::Integer) = $f(x, y)
    end
end

# Reductions

maximum_fast(a; kw...) = Base.reduce(max_fast, a; kw...)
minimum_fast(a; kw...) = Base.reduce(min_fast, a; kw...)

maximum_fast(f, a; kw...) = Base.mapreduce(f, max_fast, a; kw...)
minimum_fast(f, a; kw...) = Base.mapreduce(f, min_fast, a; kw...)

Base.reducedim_init(f, ::typeof(max_fast), A::AbstractArray, region) =
    Base.reducedim_init(f, max, A::AbstractArray, region)
Base.reducedim_init(f, ::typeof(min_fast), A::AbstractArray, region) =
    Base.reducedim_init(f, min, A::AbstractArray, region)

maximum!_fast(r::AbstractArray, A::AbstractArray; kw...) =
    maximum!_fast(identity, r, A; kw...)
minimum!_fast(r::AbstractArray, A::AbstractArray; kw...) =
    minimum!_fast(identity, r, A; kw...)

maximum!_fast(f::Function, r::AbstractArray, A::AbstractArray; init::Bool=true) =
    Base.mapreducedim!(f, max_fast, Base.initarray!(r, f, max, init, A), A)
minimum!_fast(f::Function, r::AbstractArray, A::AbstractArray; init::Bool=true) =
    Base.mapreducedim!(f, min_fast, Base.initarray!(r, f, min, init, A), A)

end
