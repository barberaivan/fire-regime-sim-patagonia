# ignition_escape/ — ignition & escape model fitting

Fits the two simpler sub-models (part of paper 2): ignition (probability of a fire starting
per unit area/time) and escape (probability a fire escapes to become large, modeled as
**binary escape/not-escape**).

> Full detail: [`../docs/ignition-escape.md`](../docs/ignition-escape.md).

| File | Role |
|------|------|
| `fit.R` | **Canonical.** Fits ignition (negative binomial) and escape (binary logistic, > 0.09 ha) via Stan; writes samples to `files/ignition/`. Needs the non-public ignition record in `data_private/` |
| `ignition_model.stan` | Canonical ignition model |
| `escape_model.stan` | Canonical escape model: binary escape/not-escape (`bernoulli_logit`) |
| `escape_ordinal_exploratory.R` | **Exploratory, not part of the canonical pipeline.** Escape as an ordinal size class (cutpoints 0.09 / 10 / 100 ha) instead of binary. A *continuation* of `fit.R`: run `fit.R` through its "Prepare data for escape model" section first, then this in the same session. Also holds the `write.csv()` that produces `data_private/ignition/ignition_size_data.csv`, which `fire_regime/simulate.R` reads |
| `escape_model_ordinal.stan` | The ordinal model, compiled by the script above; output `files/ignition/escape_model_samples_ordinal.rds` |
| `figures/` | The section's figures, written by `fit.R` |

Only `fit.R` and its two `.stan` files feed `fire_regime/`. The ordinal variant is kept because
its 10 ha cutpoint matches the size above which the spread simulator was estimated, so escape
can be redefined at that threshold without refitting; see
[`../docs/ignition-escape.md`](../docs/ignition-escape.md) for the full description.
