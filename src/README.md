# src/ — C++ (Rcpp)

In-repo C++ compiled via `Rcpp::sourceCpp()`. The main spread engine is the external
**`FireSpread`** package (`../FireSpread`); only helper C++ specific to fitting lives here.

Planned files:

| File | Role |
|------|------|
| `sample_triplets_weighted.cpp` | Samples weighted triplets (burned area, shape similarity, steps) — core of the ABC-SMC stage-1 DE-MCMC |
