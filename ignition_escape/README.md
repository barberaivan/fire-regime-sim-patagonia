# ignition_escape/ — ignition & escape model fitting

Fits the two simpler sub-models (part of paper 2): ignition (probability of a fire starting
per unit area/time) and escape (probability a fire escapes to become large, modeled as
**binary escape/not-escape**).

> Full detail: [`../docs/ignition-escape.md`](../docs/ignition-escape.md).

| File | Role |
|------|------|
| `fit.R` | Fits ignition (negative binomial) and escape (binary logistic) models via Stan; writes samples to `files/ignition/` |
| `ignition_model.stan` | Canonical ignition model |
| `escape_model.stan` | **Canonical** escape model — binary escape/not-escape (`bernoulli_logit`) |
| `escape_model_ordinal.stan` | **Abandoned/superseded** — an earlier ordinal (K size-class) formulation of escape, replaced by the binary model above. Its output, `escape_model_samples_ordinal.rds`, still sits in the store but is not read by the canonical pipeline. Can be removed later. |
| `size_model.stan` | **Abandoned** — a continuous fire-size regression (log-area, skew-normal + censoring below one-pixel-size), from before the escape question was simplified to binary. Never finished: `fit.R`'s "Fire size model" section references `sizemod`, which is used but never assigned (its `sampling()` call is commented out) and no fitted `.rds` exists to load instead. This section cannot run from a fresh session as-is. Unrelated to `spread/hierarchical_fit.R`'s own `stansteps` steps~area regression (no code link; ignition-escape work came chronologically after spread fitting). |

> **Not being worked on right now** — user is focused on the spread side next; these two
> abandoned-model notes are here so the ignition-escape section isn't confusing later, and
> so nobody redirects `size_model`/`escape_model_ordinal` work assuming it's still active.
> When this area is revisited: decide whether to delete `size_model.stan`,
> `escape_model_ordinal.stan`, and `escape_model_samples_ordinal.rds`, or finish/fix the size
> model properly.
