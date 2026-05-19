# Calculus — Key Results

A condensed reference for the results that come up most often, with just
enough context to remember why each one matters.

## The derivative

The derivative measures the instantaneous rate of change of a function:

$$
f'(x) = \lim_{h \to 0} \frac{f(x + h) - f(x)}{h}
$$

## The fundamental theorem

Differentiation and integration are inverse operations — this is what ties
the whole subject together:

$$
\int_a^b f'(x)\,dx = f(b) - f(a)
$$

## Taylor series

Any sufficiently smooth function can be expanded as a power series about a
point $a$:

$$
f(x) = \sum_{n=0}^{\infty} \frac{f^{(n)}(a)}{n!}\,(x - a)^n
$$

## The Gaussian integral

A result that appears throughout probability and physics, and which has no
elementary antiderivative:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

Keep these four within reach and most first-year problems become bookkeeping.
