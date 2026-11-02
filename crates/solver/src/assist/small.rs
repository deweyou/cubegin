use super::{AssistOptions, Solution, fail, solution, targets};
use crate::SolveError;
use cubegin_puzzle::events::{EventState, tokenize};
use serde_json::Value;
use std::sync::LazyLock;
static DATA: LazyLock<Value> =
    LazyLock::new(|| serde_json::from_str(include_str!("../../data/assist-small.json")).unwrap());
fn labels(key: &str) -> Vec<String> {
    DATA[key]["TARGETS"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap().into())
        .collect()
}
fn number(v: &Value) -> usize {
    v.as_u64().unwrap() as usize
}
fn move_table(key: &str, index: usize, mv: usize) -> usize {
    number(&DATA["pyram"]["tables"][key][index][mv])
}
fn pyra_move(mut s: [usize; 3], mv: usize) -> [usize; 3] {
    s[0] = move_table("edgePermutationMoves", s[0], mv);
    s[1] = move_table("edgeOrientationMoves", s[1], mv);
    s[2] = move_table("centerOrientationMoves", s[2], mv);
    s
}
fn pyra_dfs(s: [usize; 3], goal: usize, depth: usize, last: usize, path: &mut Vec<usize>) -> bool {
    if depth == 0 {
        return s == [goal, goal * 2, 0];
    }
    let distance = DATA["pyram"]["tables"]["pruning"][s[2] * 120 + s[0] * 4 + s[1] % 4]
        .as_i64()
        .unwrap();
    if distance > depth as i64 {
        return false;
    }
    for mv in 0..4 {
        if mv == last {
            continue;
        }
        let mut next = s;
        for turn in 0..2 {
            next = pyra_move(next, mv);
            path.push(mv * 2 + turn);
            if pyra_dfs(next, goal, depth - 1, mv, path) {
                return true;
            }
            path.pop();
        }
    }
    false
}
fn pyra(algorithm: &str, options: &AssistOptions) -> Result<Vec<Solution>, SolveError> {
    EventState::solved("pyram")?.apply(algorithm)?;
    let names = labels("pyram");
    let max = options.max_depth.unwrap_or(6);
    let mut results = Vec::new();
    for index in targets(&names, options)? {
        let faces = DATA["pyram"]["TARGET_MOVES"][index].as_str().unwrap();
        let mut states = [[0, 0, 0], [6, 12, 0], [8, 16, 0]];
        for token in tokenize(algorithm)? {
            let face = token.chars().next().unwrap();
            if face.is_lowercase() {
                continue;
            }
            let mv = faces.find(face).unwrap();
            for _ in 0..if token.ends_with('\'') { 2 } else { 1 } {
                for state in &mut states {
                    *state = pyra_move(*state, mv);
                }
            }
        }
        let mut result = None;
        'outer: for depth in 0..=max {
            for (i, s) in states.iter().enumerate() {
                let mut path = Vec::new();
                if pyra_dfs(*s, [0, 6, 8][i], depth, 4, &mut path) {
                    result = Some(
                        path.iter()
                            .map(|m| {
                                format!(
                                    "{}{}",
                                    faces.as_bytes()[m / 2] as char,
                                    if m % 2 == 1 { "'" } else { "" }
                                )
                            })
                            .collect::<Vec<_>>()
                            .join(" "),
                    );
                    break 'outer;
                }
            }
        }
        results.push(solution(
            "pyraminx-v",
            &names[index],
            &names[index],
            "",
            &result.ok_or_else(|| fail("no Pyraminx V solution within depth"))?,
        ));
    }
    Ok(results)
}
fn cube2(
    method: &str,
    algorithm: &str,
    options: &AssistOptions,
) -> Result<Vec<Solution>, SolveError> {
    let parsed = cubegin_puzzle::parse(algorithm)?;
    if parsed.iter().any(|m| !"URF".contains(m.face())) {
        return Err(fail("2x2 assist accepts URF turns only"));
    }
    let names = labels("cube2");
    let max = options.max_depth.unwrap_or(7);
    let count = options.max_solutions_per_target.unwrap_or(1);
    if count > 64 {
        return Err(fail("at most 64 solutions per target"));
    }
    let order = "RUFLDB";
    let mut movements = Vec::new();
    for (face, axis) in [('U', 0), ('R', 1), ('F', 2)] {
        for suffix in ["", "2", "'"] {
            let name = format!("{face}{suffix}");
            let permutation = tnoodle_backend::puzzle::CubeState::move_permutation(2, &name)
                .map_err(|e| fail(e.to_string()))?;
            movements.push((name, axis, permutation));
        }
    }
    let mut results = Vec::new();
    for index in targets(&names, options)? {
        let mut goal = vec![b'-'; 24];
        let face = order.find(&names[index]).unwrap();
        if method == "222-face" {
            for i in 0..4 {
                goal[face * 4 + i] = face as u8;
            }
        } else {
            for coordinate in DATA["cube2"]["layers"][&names[index]].as_array().unwrap() {
                let face = order.find(coordinate[0].as_str().unwrap()).unwrap();
                let row = number(&coordinate[1]);
                let col = number(&coordinate[2]);
                goal[face * 4 + row * 2 + col] = face as u8;
            }
        }
        let mut state = goal.clone();
        for token in algorithm.split_whitespace() {
            let permutation = tnoodle_backend::puzzle::CubeState::move_permutation(2, token)
                .map_err(|e| fail(e.to_string()))?;
            state = permutation.iter().map(|i| state[*i]).collect();
        }
        let answers = super::mask::custom_search(vec![goal], movements.clone(), &state, max, count);
        if answers.is_empty() {
            return Err(fail(format!("no {method} solution for {}", names[index])));
        }
        for a in answers {
            results.push(solution(
                method,
                &names[index],
                &format!(
                    "{} {}",
                    names[index],
                    if method == "222-face" {
                        "face"
                    } else {
                        "layer"
                    }
                ),
                "",
                &a,
            ));
        }
    }
    Ok(results)
}
fn skewb_goal(state: &[u8], target: usize, names: &[String]) -> bool {
    if state[target * 5..target * 5 + 5]
        .iter()
        .any(|v| usize::from(*v) != target)
    {
        return false;
    }
    let name = &names[target];
    let actual = DATA["skewb"]["FACE_CORNER_ORDER"][name]
        .as_array()
        .unwrap()
        .iter()
        .map(|corner| {
            DATA["skewb"]["CORNER_STICKERS"][corner.as_str().unwrap()]
                .as_array()
                .unwrap()
                .iter()
                .fold(0u64, |mask, c| {
                    let face = names
                        .iter()
                        .position(|f| f == c["face"].as_str().unwrap())
                        .unwrap();
                    mask | (1 << state[face * 5 + number(&c["sticker"])])
                })
        })
        .collect::<Vec<_>>();
    let expected = DATA["skewb"]["SOLVED_CORNER_ORDERS"][name]
        .as_array()
        .unwrap();
    (0..4).any(|offset| {
        actual
            .iter()
            .enumerate()
            .all(|(i, v)| *v == expected[(i + offset) % 4].as_u64().unwrap())
    })
}
// Search context follows the legacy coordinate implementation.
#[allow(clippy::too_many_arguments)]
fn skewb_dfs(
    state: &[u8],
    target: usize,
    names: &[String],
    moves: &[(String, Vec<usize>)],
    depth: usize,
    last: usize,
    path: &mut Vec<usize>,
    seen: &mut std::collections::HashMap<Vec<u8>, usize>,
) -> bool {
    if skewb_goal(state, target, names) {
        return true;
    }
    if depth == 0 {
        return false;
    }
    if seen.get(state).is_some_and(|remaining| *remaining > depth) {
        return false;
    }
    seen.insert(state.to_vec(), depth);
    for (i, (_, permutation)) in moves.iter().enumerate() {
        if i / 2 == last {
            continue;
        }
        let next = permutation.iter().map(|i| state[*i]).collect::<Vec<_>>();
        path.push(i);
        if skewb_dfs(&next, target, names, moves, depth - 1, i / 2, path, seen) {
            return true;
        }
        path.pop();
    }
    false
}
fn skewb(algorithm: &str, options: &AssistOptions) -> Result<Vec<Solution>, SolveError> {
    let EventState::Skewb(state) = EventState::solved("skewb")?.apply(algorithm)? else {
        unreachable!()
    };
    let names = labels("skewb");
    let state = (0..6)
        .flat_map(|f| {
            (0..5).map({
                let state = &state;
                move |i| state.sticker(f, i)
            })
        })
        .collect::<Vec<_>>();
    let mut movements = Vec::new();
    for face in ["R", "U", "L", "B"] {
        for suffix in ["", "'"] {
            let token = format!("{face}{suffix}");
            movements.push((
                token.clone(),
                tnoodle_backend::puzzle::SkewbState::move_permutation(&token)
                    .map_err(|e| fail(e.to_string()))?,
            ));
        }
    }
    let mut results = Vec::new();
    for target in targets(&names, options)? {
        let mut found = None;
        for depth in 0..=options.max_depth.unwrap_or(7) {
            let mut path = Vec::new();
            if skewb_dfs(
                &state,
                target,
                &names,
                &movements,
                depth,
                4,
                &mut path,
                &mut Default::default(),
            ) {
                found = Some(
                    path.iter()
                        .map(|i| movements[*i].0.clone())
                        .collect::<Vec<_>>()
                        .join(" "),
                );
                break;
            }
        }
        results.push(solution(
            "skewb-face",
            &names[target],
            &format!("{} face", names[target]),
            "",
            &found.ok_or_else(|| fail("no Skewb face solution within depth"))?,
        ));
    }
    Ok(results)
}
fn rotate(v: u32) -> u32 {
    ((v << 1) & 0xffe) | ((v >> 11) & 1)
}
fn top(s: u32) -> u32 {
    ((s >> 12) << 12) | rotate(s & 0xfff)
}
fn bottom(s: u32) -> u32 {
    (rotate(s >> 12) << 12) | (s & 0xfff)
}
fn twist(s: u32) -> u32 {
    let top = s & 0xfff;
    let bot = s >> 12;
    (((bot & 0xf80) | (top & 0x7f)) << 12) | ((top & 0xf80) | (bot & 0x7f))
}
fn slashable(s: u32) -> bool {
    let a = s & 0xfff;
    let b = s >> 12;
    a & 1 != 0 && a & 64 != 0 && b & 1 != 0 && b & 64 != 0
}
fn shape_index(s: u32) -> Option<usize> {
    DATA["sq1"]["shapeIndexes"]
        .as_array()
        .unwrap()
        .binary_search_by_key(&u64::from(s), |v| v.as_u64().unwrap())
        .ok()
}
fn shape(algorithm: &str) -> Result<u32, SolveError> {
    let mut s = 7191405;
    for t in tokenize(algorithm)? {
        if t == "/" {
            s = twist(s);
        } else {
            let values = t
                .trim_matches(['(', ')'])
                .split(',')
                .map(str::parse::<i32>)
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| fail(e.to_string()))?;
            if values.len() != 2 {
                return Err(fail("invalid Square-1 tuple"));
            }
            for _ in 0..(values[0] + 12).rem_euclid(12) {
                s = top(s);
            }
            for _ in 0..(values[1] + 12).rem_euclid(12) {
                s = bottom(s);
            }
        }
    }
    Ok(s)
}
fn signed(v: i32) -> i32 {
    if v > 6 { v - 12 } else { v }
}
fn twist_dfs(s: u32, depth: usize, slash: bool, path: &mut Vec<i32>) -> bool {
    if depth == 0 {
        return s == 7191405;
    }
    let Some(index) = shape_index(s) else {
        return false;
    };
    if DATA["sq1"]["twistPruning"][index].as_i64().unwrap() > depth as i64 {
        return false;
    }
    let mut a = s;
    for u in 0..12 {
        if u != 0 {
            path.push(u);
        }
        let mut b = a;
        for d in 0..12 {
            if d != 0 {
                path.push(-d);
            }
            if (!slash || u != 0 || d != 0) && slashable(b) {
                path.push(0);
                if twist_dfs(twist(b), depth - 1, true, path) {
                    return true;
                }
                path.pop();
            }
            if d != 0 {
                path.pop();
            }
            b = bottom(b);
        }
        if u != 0 {
            path.pop();
        }
        a = top(a);
    }
    false
}
fn square(
    method: &str,
    algorithm: &str,
    options: &AssistOptions,
) -> Result<Vec<Solution>, SolveError> {
    if options
        .targets
        .as_ref()
        .is_some_and(|v| v.iter().any(|v| v != "shape"))
    {
        return Err(fail("unknown Square-1 shape target"));
    }
    EventState::solved("sq1")?.apply(algorithm)?;
    let mut s = shape(algorithm)?;
    let max = options
        .max_depth
        .unwrap_or(if method.ends_with("ftm") { 14 } else { 12 });
    let mut output = Vec::new();
    if method.ends_with("ftm") {
        loop {
            let index = shape_index(s).ok_or_else(|| fail("Square-1 state is not slashable"))?;
            let depth = DATA["sq1"]["faceTurnPruning"][index].as_i64().unwrap();
            if depth <= 0 {
                break;
            }
            if output.len() > max {
                return Err(fail("Square-1 shape depth exceeded"));
            }
            let distance = |state: u32| {
                shape_index(state).map(|i| DATA["sq1"]["faceTurnPruning"][i].as_i64().unwrap())
            };
            let mut advanced = false;
            if slashable(s) && distance(twist(s)) == Some(depth - 1) {
                s = twist(s);
                output.push("/".to_owned());
                advanced = true;
            }
            let mut u = 0;
            let mut a = s;
            for turn in 0..12 {
                if distance(a).is_some_and(|d| Some(d + 1) == distance(s)) {
                    u = turn;
                    s = a;
                    advanced = true;
                    break;
                }
                a = top(a);
            }
            let mut d = 0;
            let mut a = s;
            for turn in 0..12 {
                if distance(a).is_some_and(|d| Some(d + 1) == distance(s)) {
                    d = turn;
                    s = a;
                    advanced = true;
                    break;
                }
                a = bottom(a);
            }
            if u != 0 || d != 0 {
                output.push(format!("({},{})", signed(u), signed(d)));
            }
            if !advanced {
                return Err(fail("Square-1 shape search made no progress"));
            }
        }
    } else {
        let mut found = None;
        for depth in 0..=max {
            let mut path = Vec::new();
            if twist_dfs(s, depth, false, &mut path) {
                found = Some(path);
                break;
            }
        }
        let path = found.ok_or_else(|| fail("no Square-1 twist solution within depth"))?;
        let (mut u, mut d) = (0, 0);
        for value in path {
            if value > 0 {
                u = signed(value);
            } else if value < 0 {
                d = signed(-value);
            } else {
                if u != 0 || d != 0 {
                    output.push(format!("({u},{d})"));
                }
                output.push("/".into());
                u = 0;
                d = 0;
            }
        }
        if u != 0 || d != 0 {
            output.push(format!("({u},{d})"));
        }
    }
    let a = output.join(" ");
    let mut answer = solution(method, "shape", "shape", "", &a);
    answer.depth = output.len();
    answer.metric.ftm = output.len();
    answer.metric.qtm = output.len();
    Ok(vec![answer])
}
pub fn solve(
    event: &str,
    method: &str,
    algorithm: &str,
    options: &AssistOptions,
) -> Result<Vec<Solution>, SolveError> {
    match event {
        "222" => cube2(method, algorithm, options),
        "pyram" => pyra(algorithm, options),
        "skewb" => skewb(algorithm, options),
        _ => square(method, algorithm, options),
    }
}
