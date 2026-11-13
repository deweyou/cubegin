# Shared migration fixtures

[![English](https://img.shields.io/badge/English-blue)](README.md) [![中文](https://img.shields.io/badge/%E4%B8%AD%E6%96%87-blue)](README_ZH.md)

These fixtures support the current Rust implementation and SDK verification. They
reference legacy Cubegin commit `79a1e4c4c5239fbcda8cccf313a81b8d7d430a97` as a
behavior baseline; they do not establish the legacy implementation as ground truth.

| File | Current purpose |
| --- | --- |
| `states.json` | 22 original 3x3 outer-turn cases, shared by Rust and SDK consumers |
| `events.json` | 223 puzzle-specific state cases for the event API, including wide/slice turns, rotations and extended Clock orientation |
| `legacy-catalog.json` | The reference catalog of 18 standard event IDs and 94 training types |
| `fto-conventions.json` | FTO facelet/color convention mapping between legacy and backend representations |
| `fto-coordinate-conventions.json` | FTO cubie-coordinate convention mappings used during migration |

`states.json` converts legacy face order RUFLDB to URFDLB (indices 1,0,2,4,3,5).
Each face is row-major viewed from outside. That original 3x3 API accepts outer
turns only; the event API separately supports puzzle-specific notation, wide/slice
turns and rotations. See [SDK contracts](../docs/sdk.md).

Rust also checks legality, group identities and solution replay. Packaged copies of
state fixtures live under `crates/puzzle/tests/fixtures/`; keep them synchronized.
Training and auxiliary oracle fixtures live with their crate tests. See
[verification](../docs/testing.md) for the legacy oracle and all acceptance layers.
