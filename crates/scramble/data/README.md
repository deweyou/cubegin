# Training tables

`legacy-training.json` and `catalog.json` were extracted from Cubegin commit
`79a1e4c4c5239fbcda8cccf313a81b8d7d430a97`,
`packages/scramble-core/src/{catalog,generators/training-*}.ts`.
They contain case IDs, weights, constraints, coordinates and subgroup move sets.
Functions were translated to Rust; no JavaScript runtime is retained.

The 188 seed/type fixtures in `../tests/fixtures/training.json` were independently
accepted by the old 11-family `does*TrainingStateMatch` validators (seeds 42 and 7,
94 types each). This validates those samples, not a proof of all reachable states.
Tests also choose the last case in each selectable family and exercise orientation.
