# Player geometry

`models.json` contains immutable geometry and primitive move permutations extracted
from Cubegin `79a1e4c4c5239fbcda8cccf313a81b8d7d430a97`,
`packages/player/src/puzzles`. It is declarative data, not a JavaScript runtime.

Cube geometry is generated from lattice coordinates. Pyraminx, Skewb, Megaminx
and FTO geometry follows the legacy static polyhedron adapters. The first three
reference cubing.js PuzzleGeometry (MPL-2.0 OR GPL-3.0-or-later; GPL option).
Square-1 uses closed wedge pieces; Clock includes physical hands, pins and case.

Rust owns move tracking, cumulative quaternion poses, Square-1 wedge exchange,
Clock orientation and interpolation. JSON output schema is versioned by
`schemaVersion: 1`. Native products can render piece geometry with their own GPU
backend, or use deterministic SVG frames. No JavaScript adapter runs in native SDKs.
