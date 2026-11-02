//! Training rules and case identities ported from legacy commit 79a1e4c.
use cubegin_puzzle::{
    CORNERS, Cube, EDGES, PuzzleError, SOLVED, events::EventState, inverse, parity,
};
use cubegin_solver::SolveError;
use rand::{Rng, SeedableRng, seq::SliceRandom};
use rand_chacha::ChaCha8Rng;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::LazyLock;
use tnoodle_backend::java::JavaRandom;
use tnoodle_backend::puzzle::{
    PyraminxSolver, PyraminxSolverState, SkewbSolver, SkewbSolverState, TwoByTwoSolver,
    TwoByTwoState,
};
static TABLES: LazyLock<Value> =
    LazyLock::new(|| serde_json::from_str(include_str!("../data/legacy-training.json")).unwrap());
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TrainingOptions {
    pub enabled_case_ids: Option<Vec<String>>,
    #[serde(default)]
    pub natural: bool,
    pub orientation: Option<Orientation>,
}
#[derive(Debug, Serialize)]
pub struct TrainingScramble {
    pub scramble_type_id: String,
    pub event_id: String,
    pub algorithm: String,
    pub case_id: Option<String>,
    pub state: Value,
    pub seed: u32,
    pub orientation: Option<Orientation>,
}
#[derive(Debug, Serialize)]
pub struct Case {
    pub id: String,
    pub natural_weight: u64,
}
fn error(reason: impl Into<String>) -> SolveError {
    SolveError::InvalidInput(PuzzleError::InvalidState(reason.into()))
}
fn arr(v: &Value) -> &[Value] {
    v.as_array().map(Vec::as_slice).unwrap_or(&[])
}
fn table(family: &str, key: &str) -> &'static Value {
    &TABLES[family][key]
}
fn raw_cases(id: &str) -> Vec<Value> {
    let value = if id.starts_with("222.") {
        &table("two-by-two", "CASES_BY_TYPE")[id]
    } else if id.starts_with("333.") {
        &table("three-by-three", "CASES_BY_TYPE")[id]
    } else if id == "444.poll" {
        table("four-by-four", "POLL_CASES")
    } else if id == "444.ppll" {
        table("four-by-four", "PPLL_CASES")
    } else if id == "pyram.l4e" {
        table("pyraminx", "L4E_CASES")
    } else if id == "skewb.l2l" {
        table("skewb", "L2L_CASES")
    } else if id == "sq1.csp" {
        table("square-one", "CSP_CASES")
    } else if id == "sq1.pbl" {
        table("square-one", "PBL_CASES")
    } else if id.starts_with("minx.") {
        &table("megaminx", "CASES_BY_TYPE")[id]
    } else if id.starts_with("fto.") {
        &table("fto", "CASES_BY_TYPE")[id]
    } else {
        &Value::Null
    };
    arr(value).to_vec()
}
pub fn cases(id: &str) -> Vec<Case> {
    raw_cases(id)
        .iter()
        .map(|c| Case {
            id: c["id"].as_str().unwrap().into(),
            natural_weight: c["naturalWeight"].as_u64().unwrap_or(1),
        })
        .collect()
}
fn select(
    id: &str,
    options: &TrainingOptions,
    rng: &mut impl Rng,
) -> Result<Option<Value>, SolveError> {
    let all = raw_cases(id);
    if all.is_empty() {
        if options.enabled_case_ids.is_some() {
            return Err(error("this type has no selectable cases"));
        }
        return Ok(None);
    }
    let enabled = if let Some(ids) = &options.enabled_case_ids {
        if ids.is_empty() {
            return Err(error("enabled_case_ids must not be empty"));
        }
        let mut seen = std::collections::HashSet::new();
        let mut selected = Vec::new();
        for id in ids {
            if !seen.insert(id) {
                return Err(error("duplicate enabled case ID"));
            }
            selected.push(
                all.iter()
                    .find(|c| c["id"].as_str() == Some(id))
                    .cloned()
                    .ok_or_else(|| error(format!("unknown case ID: {id}")))?,
            );
        }
        selected
    } else {
        all
    };
    if !options.natural {
        return Ok(Some(enabled[rng.gen_range(0..enabled.len())].clone()));
    }
    let total: u64 = enabled
        .iter()
        .map(|c| c["naturalWeight"].as_u64().unwrap_or(1))
        .sum();
    if total == 0 {
        return Err(error("case weights must be positive"));
    }
    let mut draw = rng.gen_range(0..total);
    for case in enabled {
        let weight = case["naturalWeight"].as_u64().unwrap_or(1);
        if draw < weight {
            return Ok(Some(case));
        }
        draw -= weight;
    }
    unreachable!()
}
pub fn generate_training(
    id: &str,
    seed: u32,
    options: &TrainingOptions,
) -> Result<TrainingScramble, SolveError> {
    if !type_catalog()[id].is_object() || type_catalog()[id]["kind"] == "official" {
        return Err(error(format!("unknown training ID: {id}")));
    }
    let mut rng = ChaCha8Rng::seed_from_u64(seed.into());
    let orientation = resolve_orientation(id, options.orientation.as_ref(), &mut rng)?;
    let selected = select(id, options, &mut rng)?;
    let event = id
        .split('.')
        .next()
        .ok_or_else(|| error("invalid training ID"))?;
    let algorithm = if id.starts_with("333.") {
        let subgroup = &table("three-by-three", "SUBGROUP_MOVES")[id];
        if !subgroup.is_null() {
            let moves = arr(subgroup)
                .iter()
                .flat_map(|m| {
                    let m = m.as_str().unwrap();
                    if m.ends_with('2') {
                        vec![m.to_owned()]
                    } else {
                        vec![m.into(), format!("{m}2"), format!("{m}'")]
                    }
                })
                .collect::<Vec<String>>();
            super::subgroup::sample(
                "333",
                &moves,
                if arr(subgroup).len() <= 2 { 6 } else { 5 },
                80_000,
                4,
                &mut rng,
            )?
        } else {
            let constraints = selected
                .as_ref()
                .map(|c| &c["constraints"])
                .unwrap_or(&table("three-by-three", "THREE_BY_THREE_CONSTRAINTS")[id]);
            if constraints.is_null() {
                return Err(error(format!("unknown training ID: {id}")));
            }
            let mut result = None;
            for _ in 0..20 {
                let state = constrained_three(constraints, &mut rng)?;
                let alg = inverse(&cubegin_solver::solve(&state)?)?;
                if alg.split_whitespace().count() >= 3 {
                    result = Some(alg);
                    break;
                }
            }
            result.ok_or_else(|| error("could not sample a non-degenerate training state"))?
        }
    } else if id.starts_with("222.") {
        let solver = TwoByTwoSolver::new();
        if id == "222.no_bar" {
            let mut result = None;
            for _ in 0..1000 {
                let s = solver.random_state(&mut JavaRandom::new(rng.r#gen()));
                let alg = solver
                    .generate_exactly(s, 11)
                    .ok_or_else(|| error("2x2 training search failed"))?;
                if no_bar("222", &alg)? {
                    result = Some(alg);
                    break;
                }
            }
            result.ok_or_else(|| error("no-bar sampling exhausted"))?
        } else {
            let c = &selected
                .as_ref()
                .ok_or_else(|| error("unknown 2x2 training type"))?["state"];
            solver
                .generate_exactly(
                    TwoByTwoState {
                        permutation: c["permutation"].as_i64().unwrap() as i32,
                        orientation: c["orientation"].as_i64().unwrap() as i32,
                    },
                    11,
                )
                .ok_or_else(|| error("2x2 training search failed"))?
        }
    } else if id.starts_with("pyram.") {
        let solver = PyraminxSolver::new();
        let mut random = JavaRandom::new(rng.r#gen());
        if id == "pyram.four_tips" {
            let s = PyraminxSolverState {
                tips: rng.gen_range(1..81),
                ..Default::default()
            };
            solver
                .generate_exactly(s, 0, false, &mut random)
                .ok_or_else(|| error("tip search failed"))?
        } else if id == "pyram.no_bar" {
            let mut result = None;
            for _ in 0..1000 {
                let s = solver.random_state(&mut random);
                let alg = solver
                    .generate_exactly(s, 11, false, &mut random)
                    .ok_or_else(|| error("pyraminx search failed"))?;
                if no_bar("pyram", &alg)? {
                    result = Some(alg);
                    break;
                }
            }
            result.ok_or_else(|| error("no-bar sampling exhausted"))?
        } else {
            let c = &selected
                .as_ref()
                .ok_or_else(|| error("unknown pyraminx training type"))?["state"];
            let s = PyraminxSolverState {
                edge_perm: c["edgePerm"].as_i64().unwrap() as i32,
                edge_orient: c["edgeOrient"].as_i64().unwrap() as i32,
                corner_orient: c["cornerOrient"].as_i64().unwrap() as i32,
                tips: rng.gen_range(0..81),
            };
            solver
                .generate_exactly(s, 11, false, &mut random)
                .ok_or_else(|| error("pyraminx search failed"))?
        }
    } else if id.starts_with("skewb.") {
        let solver = SkewbSolver::new();
        let mut random = JavaRandom::new(rng.r#gen());
        if id == "skewb.no_bar" {
            let mut result = None;
            for _ in 0..1000 {
                let s = solver.random_state(&mut random);
                let alg = solver
                    .generate_exactly(s, 11, &mut random)
                    .ok_or_else(|| error("skewb search failed"))?;
                if no_bar("skewb", &alg)? {
                    result = Some(alg);
                    break;
                }
            }
            result.ok_or_else(|| error("no-bar sampling exhausted"))?
        } else {
            let selected_case = selected
                .as_ref()
                .ok_or_else(|| error("unknown skewb training type"))?;
            let oriented = orientation.as_ref().map(|o| {
                let face = table("skewb", "SKEWB_FACE_BY_COLOR")[&o.bottom_color]
                    .as_u64()
                    .unwrap() as usize;
                let states = arr(&table("skewb", "ORIENTED_L2L_STATES")[face]);
                let index = raw_cases(id)
                    .iter()
                    .position(|c| c["id"] == selected_case["id"])
                    .unwrap();
                states[index % states.len()].clone()
            });
            let c = oriented.as_ref().unwrap_or(&selected_case["state"]);
            solver
                .generate_exactly(
                    SkewbSolverState {
                        perm: c["perm"].as_i64().unwrap() as i32,
                        twst: c["twst"].as_i64().unwrap() as i32,
                    },
                    11,
                    &mut random,
                )
                .ok_or_else(|| error("skewb search failed"))?
        }
    } else if id.ends_with(".edge_pairing") {
        edge_pairing(
            event.parse::<String>().unwrap()[..1]
                .parse()
                .map_err(|_| error("invalid big cube type"))?,
            &mut rng,
        )?
    } else if id == "444.subset.rruu" {
        let moves = ["R", "R2", "R'", "Rw", "Rw2", "Rw'", "U", "U2", "U'"].map(str::to_owned);
        super::subgroup::sample("444", &moves, 5, 100_000, 4, &mut rng)?
    } else if id.starts_with("444.") {
        four_by_four(id, selected.as_ref(), &mut rng)?
    } else if id.starts_with("sq1.") {
        square_one(id, selected.as_ref(), &mut rng)?
    } else if id.starts_with("fto.") {
        fto(id, selected.as_ref(), &mut rng)?
    } else if id.starts_with("minx.") {
        megaminx(id, selected.as_ref(), &mut rng)?
    } else {
        return Err(error(format!("unknown training ID: {id}")));
    };
    let algorithm = if let Some(o) = &orientation {
        if event == "skewb" {
            algorithm
        } else {
            transform_orientation(&algorithm, o)?
        }
    } else {
        algorithm
    };
    let state = EventState::solved(event)?.apply(&algorithm)?.data();
    Ok(TrainingScramble {
        scramble_type_id: id.into(),
        event_id: event.into(),
        algorithm,
        case_id: selected.and_then(|c| c["id"].as_str().map(str::to_owned)),
        state,
        seed,
        orientation,
    })
}
fn expand(part: &Value, n: usize, permutation: bool) -> Vec<i32> {
    if part.as_str() == Some("solved") {
        (0..n)
            .map(|i| if permutation { i as i32 } else { 0 })
            .collect()
    } else if part.is_array() {
        arr(part)
            .iter()
            .map(|v| v.as_i64().unwrap() as i32)
            .collect()
    } else {
        vec![-1; n]
    }
}
fn sample_permutation(mask: &[i32], rng: &mut impl Rng) -> Vec<usize> {
    let mut free = (0..mask.len())
        .filter(|i| !mask.contains(&(*i as i32)))
        .collect::<Vec<_>>();
    free.shuffle(rng);
    let mut it = free.into_iter();
    mask.iter()
        .map(|v| {
            if *v < 0 {
                it.next().unwrap()
            } else {
                *v as usize
            }
        })
        .collect()
}
fn sample_orientation(
    mask: &[i32],
    modulus: usize,
    rng: &mut impl Rng,
) -> Result<Vec<usize>, SolveError> {
    let mut values = mask
        .iter()
        .map(|v| {
            if *v < 0 {
                rng.gen_range(0..modulus)
            } else {
                *v as usize
            }
        })
        .collect::<Vec<_>>();
    let sum = values.iter().sum::<usize>() % modulus;
    if let Some(i) = mask.iter().rposition(|v| *v < 0) {
        values[i] = (values[i] + modulus - sum) % modulus;
    } else if sum != 0 {
        return Err(error("impossible orientation constraints"));
    }
    Ok(values)
}
fn constrained_three(c: &Value, rng: &mut impl Rng) -> Result<String, SolveError> {
    let cp_mask = expand(&c["cornerPermutation"], 8, true);
    let ep_mask = expand(&c["edgePermutation"], 12, true);
    for _ in 0..1000 {
        let cp = sample_permutation(&cp_mask, rng);
        let ep = sample_permutation(&ep_mask, rng);
        if parity(&cp) != parity(&ep) {
            continue;
        }
        let co = sample_orientation(&expand(&c["cornerOrientation"], 8, false), 3, rng)?;
        let eo = sample_orientation(&expand(&c["edgeOrientation"], 12, false), 2, rng)?;
        let mut facelets = SOLVED.as_bytes().to_vec();
        for i in 0..8 {
            for j in 0..3 {
                facelets[CORNERS[i][(j + co[i]) % 3]] = SOLVED.as_bytes()[CORNERS[cp[i]][j]];
            }
        }
        for i in 0..12 {
            for j in 0..2 {
                facelets[EDGES[i][(j + eo[i]) % 2]] = SOLVED.as_bytes()[EDGES[ep[i]][j]];
            }
        }
        let state = String::from_utf8(facelets).unwrap();
        Cube::from_facelets(&state)?;
        return Ok(state);
    }
    Err(error("impossible permutation constraints"))
}
fn edge_pairing(size: usize, rng: &mut impl Rng) -> Result<String, SolveError> {
    let spec = &table("four-by-four", "EDGE_PAIRING_TEMPLATE_SPECS")[size.to_string()];
    if spec.is_null() {
        return Err(error("edge pairing requires size 4..7"));
    }
    let strings = |v: &Value| {
        arr(v)
            .iter()
            .map(|v| v.as_str().unwrap().to_owned())
            .collect::<Vec<_>>()
    };
    let mut moves = strings(&spec["start"]);
    let misalign = strings(&spec["misalignmentMoves"]);
    let mut totals = vec![0; misalign.len()];
    let mut outer = [0; 2];
    for _ in 0..8 {
        let amounts = loop {
            let v = (0..misalign.len())
                .map(|_| rng.gen_range(0..4))
                .collect::<Vec<_>>();
            if v.iter().any(|v| *v != 0) {
                break v;
            }
        };
        for (i, a) in amounts.into_iter().enumerate() {
            if a != 0 {
                moves.push(turn(&misalign[i], a));
                totals[i] = (totals[i] + a) % 4;
            }
        }
        let triggers = arr(table("four-by-four", "EDGE_PAIRING_TRIGGERS"));
        let trigger = &triggers[rng.gen_range(0..triggers.len())];
        let face = rng.gen_range(0..2);
        let a = rng.gen_range(1..4);
        moves.push(trigger[0].as_str().unwrap().into());
        moves.push(turn(if face == 0 { "U" } else { "D" }, a));
        moves.push(trigger[1].as_str().unwrap().into());
        outer[face] = (outer[face] + a) % 4;
    }
    for (i, m) in misalign.iter().enumerate() {
        let a = (4 - totals[i]) % 4;
        if a != 0 {
            moves.push(turn(m, a));
        }
    }
    for (i, m) in ["U", "D"].iter().enumerate() {
        let a = (4 - outer[i]) % 4;
        if a != 0 {
            moves.push(turn(m, a));
        }
    }
    let endings = arr(&spec["endings"]);
    moves.extend(strings(&endings[rng.gen_range(0..endings.len())]));
    Ok(moves.join(" "))
}
fn turn(face: &str, amount: usize) -> String {
    format!(
        "{face}{}",
        match amount {
            2 => "2",
            3 => "'",
            _ => "",
        }
    )
}
fn no_bar(event: &str, algorithm: &str) -> Result<bool, SolveError> {
    let state = EventState::solved(event)?.apply(algorithm)?.data();
    let faces = arr(&state["image"]);
    Ok(match event {
        "222" => faces.iter().all(|face| {
            let f = arr(face).iter().flat_map(arr).collect::<Vec<_>>();
            f[0] != f[1] && f[0] != f[2] && f[3] != f[1] && f[3] != f[2]
        }),
        "skewb" => faces
            .iter()
            .all(|face| arr(face)[1..].iter().all(|c| *c != face[0])),
        // Exact Pyraminx no-bar predicate is supplied by the coordinate adapter below.
        "pyram" => pyraminx_no_bar(algorithm)?,
        _ => false,
    })
}
fn pyraminx_no_bar(algorithm: &str) -> Result<bool, SolveError> {
    let EventState::Pyram(state) = EventState::solved("pyram")?.apply(algorithm)? else {
        unreachable!()
    };
    let s = state.to_solver_state();
    let (ep, eo, co) = tnoodle_backend::puzzle::pyraminx_coords::decode(s);
    let corners = [[3, 16, 11], [4, 23, 15], [5, 9, 22], [10, 17, 21]];
    let edges = [[1, 7], [2, 14], [0, 18], [6, 12], [8, 20], [13, 19]];
    let mut f = [0; 24];
    for i in 0..4 {
        for j in 0..3 {
            f[corners[i][(j + co[i]) % 3]] = corners[i][j] / 6;
        }
    }
    for i in 0..6 {
        for j in 0..2 {
            f[edges[i][(j + eo[i]) % 2]] = edges[ep[i]][j] / 6;
        }
    }
    let neighbors = [4, 2, 3, 1, 5, 0];
    for edge in edges {
        for d in 0..2 {
            let a = edge[d];
            let b = edge[d ^ 1];
            let ai = neighbors.iter().position(|p| *p == a % 6).unwrap();
            let bi = neighbors.iter().position(|p| *p == b % 6).unwrap();
            let an = a / 6 * 6 + neighbors[(ai + 5) % 6];
            let bn = b / 6 * 6 + neighbors[(bi + 1) % 6];
            if f[an] == f[a] && f[bn] == f[b] {
                return Ok(false);
            }
        }
    }
    Ok(true)
}

fn numbers(v: &Value) -> Vec<usize> {
    arr(v)
        .iter()
        .map(|v| v.as_u64().unwrap() as usize)
        .collect()
}
fn four_by_four(id: &str, case: Option<&Value>, rng: &mut impl Rng) -> Result<String, SolveError> {
    let (mut ep, mut ct, mut cp, mut co) = if let Some(c) = case {
        let s = &c["state"];
        (
            numbers(&s["edgePermutation"]),
            numbers(&s["centerColors"]),
            numbers(&s["cornerPermutation"]),
            numbers(&s["cornerOrientation"]),
        )
    } else {
        let mut mask = table("four-by-four", "PARTIAL_MASKS")[id].clone();
        if id == "444.yau.ud_3_edges" {
            mask = serde_json::json!({"centers":0xffff00,"edges":0xff0ff0|(0x1001<<rng.gen_range(0..4)),"corners":0xff});
        }
        if id == "444.hoya.rldx_centers" || id == "444.hoya.rldx_cross" {
            mask = serde_json::json!({"centers":0x0000f0|(0xf00<<(rng.gen_range(0..2)*4)),"edges":if id.ends_with("cross"){0xff0ff0}else{0xffffff},"corners":0xff});
        }
        if mask.is_null() {
            return Err(error("unknown 4x4 training type"));
        }
        let shuffle = |values: Vec<usize>, bits: u64, rng: &mut dyn rand::RngCore| {
            let mut out = values;
            let slots = (0..out.len())
                .filter(|i| bits & (1 << i) != 0)
                .collect::<Vec<_>>();
            let mut values = slots.iter().map(|i| out[*i]).collect::<Vec<_>>();
            values.shuffle(rng);
            for (i, j) in slots.into_iter().enumerate() {
                out[j] = values[i];
            }
            out
        };
        let center_solved = (0..24)
            .map(|i| [0, 3, 2, 5, 1, 4][i / 4])
            .collect::<Vec<_>>();
        let ep = shuffle((0..24).collect(), mask["edges"].as_u64().unwrap(), rng);
        let ct = shuffle(center_solved, mask["centers"].as_u64().unwrap(), rng);
        let cp = shuffle((0..8).collect(), mask["corners"].as_u64().unwrap(), rng);
        let co = sample_orientation(
            &(0..8)
                .map(|i| {
                    if mask["corners"].as_u64().unwrap() & (1 << i) != 0 {
                        -1
                    } else {
                        0
                    }
                })
                .collect::<Vec<_>>(),
            3,
            rng,
        )?;
        (ep, ct, cp, co)
    };
    let bytes = |v: &mut Vec<usize>| v.iter().map(|i| *i as u8).collect::<Vec<_>>();
    let c = tnoodle_backend::threephase::FullCube::from_parts(
        bytes(&mut ep).try_into().unwrap(),
        bytes(&mut ct).try_into().unwrap(),
        bytes(&mut cp).try_into().unwrap(),
        bytes(&mut co).try_into().unwrap(),
    )
    .ok_or_else(|| error("invalid 4x4 training coordinates"))?;
    let mut search = tnoodle_backend::threephase::Search::new();
    search.with_rotation = true;
    search.calc(c);
    Ok(search.last_solution().trim().into())
}
fn square_one(id: &str, case: Option<&Value>, rng: &mut impl Rng) -> Result<String, SolveError> {
    use tnoodle_backend::java::RandomSource;
    use tnoodle_backend::sq12phase::{FullCube, INVERSE_SOLUTION, Search};
    let cube = if id == "sq1.pbl" {
        let c = case.ok_or_else(|| error("missing PBL case"))?;
        let ep = (0x4444 - c["edgePermutation"].as_u64().unwrap()) & 0x3333;
        let cp = (0x3333 - c["cornerPermutation"].as_u64().unwrap()) & 0x3333;
        let mut cube = FullCube::new();
        for i in 0..4 {
            let shift = 12 - i * 4;
            let corner = (((cp >> shift) & 15) * 2 + 1) as i32;
            cube.set_piece(i * 3 + 1, corner);
            cube.set_piece(i * 3 + 2, corner);
            cube.set_piece((i * 3 + 3) % 12, (((ep >> shift) & 15) * 2) as i32);
        }
        cube.set_piece(24, rng.gen_range(0..2));
        cube
    } else {
        let shape = if id == "sq1.csp" {
            case.ok_or_else(|| error("missing CSP case"))?["shapeIndex"]
                .as_i64()
                .unwrap() as i32
        } else if id == "sq1.cube_shape" {
            loop {
                let i = rng.gen_range(0..3678);
                if i != 1037 {
                    break i;
                }
            }
        } else {
            return Err(error("unknown Square-1 training type"));
        };
        struct ShapeRandom {
            shape: Option<i32>,
            rng: JavaRandom,
        }
        impl RandomSource for ShapeRandom {
            fn next_bits(&mut self, bits: u32) -> i32 {
                self.rng.next_bits(bits)
            }
            fn next_int_bounded(&mut self, bound: i32) -> i32 {
                if let Some(shape) = self.shape.take() {
                    assert_eq!(bound, 3678);
                    shape
                } else {
                    self.rng.next_int_bounded(bound)
                }
            }
        }
        FullCube::random(&mut ShapeRandom {
            shape: Some(shape),
            rng: JavaRandom::new(rng.r#gen()),
        })
    };
    Search::new()
        .solution(&cube, INVERSE_SOLUTION)
        .map(|s| s.trim().into())
        .ok_or_else(|| error("Square-1 training search failed"))
}
fn even_permutation(n: usize, rng: &mut impl Rng) -> Vec<usize> {
    let mut p = (0..n).collect::<Vec<_>>();
    p.shuffle(rng);
    if parity(&p) != 0 {
        p.swap(n - 1, n - 2);
    }
    p
}
fn fto(id: &str, case: Option<&Value>, rng: &mut impl Rng) -> Result<String, SolveError> {
    const CM: [usize; 12] = [0, 1, 2, 3, 4, 5, 10, 11, 6, 7, 8, 9];
    const EM: [usize; 12] = [1, 2, 0, 11, 10, 9, 4, 3, 8, 7, 6, 5];
    const UM: [usize; 12] = [2, 1, 0, 3, 5, 4, 7, 6, 8, 11, 10, 9];
    const RM: [usize; 12] = [11, 9, 10, 8, 7, 6, 4, 3, 5, 0, 2, 1];
    for _ in 0..1000 {
        let mut cp = (0..6).collect::<Vec<_>>();
        let mut co = vec![0; 6];
        let mut ep = (0..12).collect::<Vec<_>>();
        let mut uf = ep.clone();
        let mut rl = ep.clone();
        if id == "fto.edges_only" {
            ep = even_permutation(12, rng);
        } else if id == "fto.centers_only" {
            uf = even_permutation(12, rng);
            rl = even_permutation(12, rng);
        } else if id == "fto.corners_only" {
            cp = even_permutation(6, rng);
            co = sample_orientation(&[-1; 6], 2, rng)?;
        } else if let Some(c) = case {
            for (i, v) in numbers(&c["cornerPermutation"]).into_iter().enumerate() {
                cp[i] = v;
            }
            for (i, v) in numbers(&c["cornerOrientation"]).into_iter().enumerate() {
                co[i] = v;
            }
            let positions = if id == "fto.tcp" {
                numbers(table("fto", "TCP_CENTER_POSITIONS"))
            } else if id == "fto.l3t" {
                numbers(table("fto", "L3T_CENTER_POSITIONS"))
            } else {
                numbers(table("fto", "L3T_LBT_CENTER_POSITIONS"))
            };
            let p = even_permutation(positions.len(), rng);
            if id == "fto.tcp" && (positions[p[0]] < 3 || positions[p[1]] < 3) {
                continue;
            }
            for (i, slot) in positions.iter().enumerate() {
                uf[*slot] = positions[p[i]];
            }
        } else {
            return Err(error("unknown FTO training type"));
        }
        if cp.iter().enumerate().all(|(i, v)| i == *v)
            && co.iter().all(|v| *v == 0)
            && ep.iter().enumerate().all(|(i, v)| i == *v)
            && uf.iter().enumerate().all(|(i, v)| i / 3 == *v / 3)
            && rl.iter().enumerate().all(|(i, v)| i / 3 == *v / 3)
        {
            continue;
        }
        let mut bcp = [0; 6];
        let mut bco = [0; 6];
        let mut bep = [0; 12];
        let mut buf = [0; 12];
        let mut brl = [0; 12];
        for i in 0..6 {
            let target = CM[2 * i];
            let source = CM[2 * cp[i] + co[i]];
            bcp[target / 2] = (source / 2) as i32;
            bco[target / 2] = ((source ^ target) & 1) as i32;
        }
        for i in 0..12 {
            bep[EM[i]] = EM[ep[i]] as i32;
            buf[UM[i]] = (uf[i] / 3) as i32;
            brl[RM[i]] = (3 - rl[i] / 3) as i32;
        }
        let cubie = tnoodle_backend::fto3phase::FtoCubie::from_parts(bcp, bco, bep, buf, brl)
            .ok_or_else(|| error("invalid FTO coordinates"))?;
        return Ok(tnoodle_backend::fto3phase::Search::new().solution(&cubie));
    }
    Err(error("FTO sampling exhausted"))
}

fn megaminx(id: &str, case: Option<&Value>, rng: &mut impl Rng) -> Result<String, SolveError> {
    if id == "minx.subset.ru" {
        let moves = ["U", "U2", "U2'", "U'", "R", "R2", "R2'", "R'"].map(str::to_owned);
        return super::subgroup::sample("minx", &moves, 5, 100_000, 4, rng);
    }
    if id == "minx.s2l" {
        let macros = arr(table("megaminx", "S2L_MACROS"));
        return Ok((0..18)
            .map(|_| {
                let m = macros[rng.gen_range(0..macros.len())].as_str().unwrap();
                m.replace(
                    " U ",
                    &format!(" U{} ", ["", "2", "2'", "'"][rng.gen_range(0..4)]),
                )
            })
            .collect::<Vec<_>>()
            .join(" "));
    }
    let id = case.ok_or_else(|| error("missing Megaminx training case"))?["id"]
        .as_str()
        .unwrap();
    let all = arr(table("megaminx", "EVEN_PERMUTATIONS"));
    let fixed = arr(table("megaminx", "FIXED_LAST_PERMUTATIONS"));
    let bytes = |v: &Value| {
        numbers(v)
            .into_iter()
            .map(|i| i as u8)
            .collect::<Vec<_>>()
            .try_into()
            .unwrap()
    };
    let (ep, eo, cp, co) = if let Some(suffix) = id.strip_prefix("minx.lsll.") {
        let values = suffix
            .split('-')
            .map(|v| {
                v.chars()
                    .skip_while(|c| c.is_alphabetic())
                    .collect::<String>()
                    .parse::<usize>()
                    .unwrap()
            })
            .collect::<Vec<_>>();
        let (es, cs, eo, co) = (values[0], values[1], values[2], values[3]);
        let mut choose = |slot: usize| {
            let candidates = all
                .iter()
                .filter(|v| v[slot].as_u64() == Some(5))
                .collect::<Vec<_>>();
            bytes(candidates[rng.gen_range(0..candidates.len())])
        };
        let ep = choose(es);
        let cp = choose(cs);
        let mut edge_mask = vec![-1; 6];
        edge_mask[es] = eo as i32;
        let eo = sample_orientation(&edge_mask, 2, rng)?
            .into_iter()
            .map(|v| v as u8)
            .collect::<Vec<_>>()
            .try_into()
            .unwrap();
        let mut corner_mask = vec![-1; 6];
        corner_mask[cs] = co as i32;
        let co = sample_orientation(&corner_mask, 3, rng)?
            .into_iter()
            .map(|v| v as u8)
            .collect::<Vec<_>>()
            .try_into()
            .unwrap();
        (ep, eo, cp, co)
    } else if let Some(suffix) = id.strip_prefix("minx.pll.") {
        let parts = suffix
            .split('-')
            .map(|v| v[1..].parse::<usize>().unwrap())
            .collect::<Vec<_>>();
        (
            bytes(&fixed[parts[0]]),
            [0; 6],
            bytes(&fixed[parts[1]]),
            [0; 6],
        )
    } else {
        let parts = id[8..]
            .split('-')
            .map(|v| v[2..].parse::<usize>().unwrap())
            .collect::<Vec<_>>();
        let mut ep = bytes(&fixed[rng.gen_range(0..fixed.len())]);
        let mut cp = bytes(&fixed[rng.gen_range(0..fixed.len())]);
        if parts[0] == 0 && parts[1] == 0 && ep == [0, 1, 2, 3, 4, 5] && cp == [0, 1, 2, 3, 4, 5] {
            ep = bytes(&fixed[1]);
            cp = bytes(&fixed[2]);
        }
        (
            ep,
            bytes(&table("megaminx", "EDGE_LL_ORIENTATIONS")[parts[0]]),
            cp,
            bytes(&table("megaminx", "CORNER_LL_ORIENTATIONS")[parts[1]]),
        )
    };
    cubegin_solver::megaminx::scramble(&cubegin_solver::megaminx::LsllState {
        edge_permutation: ep,
        edge_orientation: eo,
        corner_permutation: cp,
        corner_orientation: co,
    })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Orientation {
    pub bottom_color: String,
    pub front_color: Option<String>,
}
pub fn type_catalog() -> Value {
    serde_json::from_str(include_str!("../data/catalog.json")).unwrap()
}
fn resolve_orientation(
    id: &str,
    preference: Option<&Orientation>,
    rng: &mut impl Rng,
) -> Result<Option<Orientation>, SolveError> {
    let Some(p) = preference else { return Ok(None) };
    if type_catalog()[id]["orientationTarget"].is_null() {
        return Err(error("orientation is not supported for this type"));
    }
    let colors = ["white", "yellow", "red", "orange", "green", "blue"];
    let bottom = colors
        .iter()
        .position(|c| *c == p.bottom_color)
        .ok_or_else(|| error("invalid bottom color"))?;
    let adjacent = colors
        .iter()
        .enumerate()
        .filter(|(i, _)| i / 2 != bottom / 2)
        .map(|(_, c)| *c)
        .collect::<Vec<_>>();
    let front = p
        .front_color
        .clone()
        .unwrap_or_else(|| adjacent[rng.gen_range(0..4)].into());
    if !adjacent.contains(&front.as_str()) {
        return Err(error("bottom and front must be adjacent colors"));
    }
    Ok(Some(Orientation {
        bottom_color: p.bottom_color.clone(),
        front_color: Some(front),
    }))
}
fn transform_orientation(algorithm: &str, o: &Orientation) -> Result<String, SolveError> {
    let faces = ['U', 'D', 'R', 'L', 'F', 'B'];
    let colors = ["white", "yellow", "red", "orange", "green", "blue"];
    let vectors = [
        [0, 1, 0],
        [0, -1, 0],
        [1, 0, 0],
        [-1, 0, 0],
        [0, 0, 1],
        [0, 0, -1],
    ];
    let vector = |c: &str| vectors[colors.iter().position(|v| *v == c).unwrap()];
    let b = vector(&o.bottom_color);
    let f = vector(o.front_color.as_ref().unwrap());
    let r = [
        f[1] * b[2] - f[2] * b[1],
        f[2] * b[0] - f[0] * b[2],
        f[0] * b[1] - f[1] * b[0],
    ];
    let neg = |v: [i32; 3]| v.map(|c| -c);
    let mapped = [neg(b), b, r, neg(r), f, neg(f)]
        .map(|v| faces[vectors.iter().position(|x| *x == v).unwrap()]);
    algorithm
        .split_whitespace()
        .map(|token| {
            let mut amount = if token.ends_with('2') {
                2
            } else if token.ends_with('\'') {
                3
            } else {
                1
            };
            let base = token.trim_end_matches(['2', '\'']);
            let (source, special) = match base {
                "x" => ('R', 1),
                "y" => ('U', 1),
                "z" => ('F', 1),
                "M" => ('L', 2),
                "E" => ('D', 2),
                "S" => ('F', 2),
                _ => {
                    let face = base
                        .chars()
                        .find(|c| faces.contains(c))
                        .ok_or_else(|| error("invalid cube move"))?;
                    (face, 0)
                }
            };
            let face = mapped[faces.iter().position(|c| *c == source).unwrap()];
            let result = if special == 1 {
                if ['L', 'D', 'B'].contains(&face) {
                    amount = 4 - amount;
                }
                match face {
                    'R' | 'L' => "x",
                    'U' | 'D' => "y",
                    _ => "z",
                }
                .to_owned()
            } else if special == 2 {
                if ['R', 'U', 'B'].contains(&face) {
                    amount = 4 - amount;
                }
                match face {
                    'R' | 'L' => "M",
                    'U' | 'D' => "E",
                    _ => "S",
                }
                .to_owned()
            } else {
                base.replace(source, &face.to_string())
            };
            Ok(format!(
                "{result}{}",
                match amount {
                    2 => "2",
                    3 => "'",
                    _ => "",
                }
            ))
        })
        .collect::<Result<Vec<_>, SolveError>>()
        .map(|v| v.join(" "))
}
