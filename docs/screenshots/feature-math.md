# Dijkstra on Sparse Graphs

A quick note on why Dijkstra's algorithm runs in $O((V + E) \log V)$ with a
binary heap, and what changes when the graph is dense enough that you might
reach for Floyd–Warshall instead.

## Recurrence

For each vertex, we relax all outgoing edges at most once. With a binary
heap, each decrease-key is $O(\log V)$, and we do at most $E$ of them:

$$
T(V, E) = O(V \log V) + O(E \log V) = O((V + E) \log V)
$$

With a Fibonacci heap that becomes $O(E + V \log V)$, which only matters
when the graph is dense — and at dense, you'd probably just run
Floyd–Warshall ($O(V^3)$) and forget about the heap entirely.

## The relaxation loop

```mermaid
graph LR
    A[Heap pop] --> B[Mark visited]
    B --> C[Relax outgoing edges]
    C --> D[Decrease keys on improvements]
    D --> A
    style B fill:#f3a26e,stroke:#a85428,color:#1a1a1f
```

The `decrease-key` step is what dominates the cost — and what motivates the
Fibonacci-heap variant when you really do need every constant factor.
