# ignition_escape/ — ignition & escape model fitting

Fits the two simpler sub-models (part of paper 2): ignition (probability of a fire starting
per unit area/time) and escape (probability a fire escapes to become large).

> Full detail: [`../docs/ignition-escape.md`](../docs/ignition-escape.md).

Planned files (migrated from the old repo — canonical `_FWIZ` version):

| File | Role |
|------|------|
| `fit.R` | Fits ignition (negative binomial) and escape (logistic) models via Stan; writes samples to `files/` |
