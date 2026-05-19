# Renderer Benchmarks

Cold-start render time — from opening a file to the first painted preview —
measured across document sizes on an Apple M3 Pro. Each figure is the median
of 30 runs.

## By document size

| Document       | Lines  | Parse (ms) | Render (ms) | Total (ms) |
|----------------|--------|------------|-------------|------------|
| Short note     | 40     | 1.2        | 8.4         | 9.6        |
| Typical README | 220    | 3.1        | 14.7        | 17.8       |
| Design spec    | 900    | 9.8        | 41.2        | 51.0       |
| Book chapter   | 3,400  | 32.6       | 138.9       | 171.5      |
| Generated dump | 12,000 | 121.4      | 503.7       | 625.1      |

Render time scales close to linearly with document length — there is no
cliff as files grow.

## By feature

| Feature           | Off (ms) | On (ms) | Delta  |
|-------------------|----------|---------|--------|
| Syntax highlight  | 14.7     | 19.3    | +4.6   |
| KaTeX math        | 14.7     | 28.1    | +13.4  |
| Mermaid diagrams  | 14.7     | 96.5    | +81.8  |

Mermaid dominates the cost, which is why it now loads lazily: only documents
that actually contain a diagram pay for it.
