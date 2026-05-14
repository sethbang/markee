# Dijkstra on Sparse Graphs

A quick note on why Dijkstra's algorithm runs in $O((V + E) \log V)$ with a
binary heap, and what changes when the graph is dense enough that you might
reach for Floyd–Warshall instead.

## Recurrence

For each vertex, we relax all outgoing edges at most once. With a binary
heap, each decrease-key is $O(\log V)$, and we do at most $E$ of them:

$$
T(V, E) \;=\; O(V \log V) \;+\; O(E \log V) \;=\; O((V + E) \log V)
$$

With a Fibonacci heap that becomes $O(E + V \log V)$, which only matters
when the graph is dense — and at dense, you'd probably just run
Floyd–Warshall ($O(V^3)$) and forget about the heap entirely.

## The relaxation loop

```mermaid
graph LR
    A[Pop min-distance vertex u] --> B{Visited?}
    B -->|yes| A
    B -->|no| C[Mark u visited]
    C --> D[For each neighbor v of u]
    D --> E{d[u] + w&lt;u,v&gt; &lt; d[v]?}
    E -->|yes| F[Decrease d[v], push to heap]
    E -->|no| D
    F --> D
    D -->|done| A
    style C fill:#f3a26e,stroke:#a85428,color:#1a1a1f
```

The `decrease-key` step is what dominates the cost — and what motivates the
Fibonacci-heap variant when you really do need every constant factor.
