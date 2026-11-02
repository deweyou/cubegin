//! Mask search: declarative legacy stages with admissible bounded reverse BFS + IDA*.
use super::{AssistOptions, RULES, Solution, fail, solution, targets};
use crate::SolveError;
use serde_json::Value;
use std::{
    collections::HashMap,
    sync::{Arc, LazyLock, Mutex},
};
struct Pattern {
    goals: Vec<Vec<u8>>,
    moves: Vec<(String, i32, Vec<usize>)>,
    distances: HashMap<Vec<u8>, usize>,
    unknown_bound: usize,
}
static CACHE: LazyLock<Mutex<HashMap<String, Arc<Pattern>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
fn permute(state: &[u8], token: &str) -> Result<Vec<u8>, SolveError> {
    let names = RULES["stage-mask"]["MOVE_NAMES"].as_str().unwrap();
    let index = names
        .find(token.chars().next().unwrap_or(' '))
        .ok_or_else(|| fail("unknown mask turn"))?;
    let cycles = RULES["stage-mask"]["MOVE_DATA"][index]
        .as_array()
        .ok_or_else(|| fail("unknown mask turn"))?;
    let mut output = state.to_vec();
    let power = if token.ends_with('2') {
        2
    } else if token.ends_with('\'') {
        3
    } else {
        1
    };
    for cycle in cycles {
        let cycle = cycle
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_u64().unwrap() as usize)
            .collect::<Vec<_>>();
        let before = cycle.iter().map(|i| output[*i]).collect::<Vec<_>>();
        for (i, value) in before.into_iter().enumerate() {
            output[cycle[(i + power) % cycle.len()]] = value;
        }
    }
    Ok(output)
}
fn apply(state: &[u8], algorithm: &str) -> Result<Vec<u8>, SolveError> {
    let mut state = state.to_vec();
    for token in algorithm.split_whitespace() {
        state = permute(&state, token)?;
    }
    Ok(state)
}
fn pattern(goals: &[String], moves: &Value, depth: usize) -> Result<Arc<Pattern>, SolveError> {
    let key = format!("{goals:?}:{moves}:{depth}");
    if let Some(p) = CACHE.lock().unwrap().get(&key).cloned() {
        return Ok(p);
    }
    let identity = (0..54).map(|i| i as u8).collect::<Vec<_>>();
    let moves = moves
        .as_object()
        .unwrap()
        .iter()
        .map(|(name, axis)| {
            Ok((
                name.clone(),
                axis.as_i64().unwrap() as i32,
                permute(&identity, name)?
                    .into_iter()
                    .map(usize::from)
                    .collect::<Vec<_>>(),
            ))
        })
        .collect::<Result<Vec<_>, SolveError>>()?;
    let goals = goals
        .iter()
        .map(|s| s.as_bytes().to_vec())
        .collect::<Vec<_>>();
    let mut distances = HashMap::new();
    let mut queue = Vec::new();
    for goal in &goals {
        distances.insert(goal.clone(), 0);
        queue.push(goal.clone());
    }
    let mut cursor = 0;
    let mut complete = 0;
    'layers: for layer in 0..depth {
        let boundary = queue.len();
        while cursor < boundary {
            let state = queue[cursor].clone();
            for (_, _, perm) in &moves {
                let next = perm.iter().map(|i| state[*i]).collect::<Vec<_>>();
                if distances.contains_key(&next) {
                    continue;
                }
                if distances.len() >= 100_000 {
                    break 'layers;
                }
                distances.insert(next.clone(), layer + 1);
                queue.push(next);
            }
            cursor += 1;
        }
        complete = layer + 1;
        if boundary == queue.len() {
            complete = depth;
            break;
        }
    }
    let result = Arc::new(Pattern {
        goals,
        moves,
        distances,
        unknown_bound: complete + 1,
    });
    let mut cache = CACHE.lock().unwrap();
    if cache.len() >= 16 {
        cache.clear();
    }
    cache.insert(key, result.clone());
    Ok(result)
}
fn dfs(
    state: &[u8],
    remaining: usize,
    last: Option<usize>,
    path: &mut Vec<usize>,
    visited: &mut HashMap<Vec<u8>, usize>,
    p: &Pattern,
) -> bool {
    if p.distances.get(state).copied().unwrap_or(p.unknown_bound) > remaining {
        return false;
    }
    if remaining == 0 {
        return p.goals.iter().any(|goal| goal == state);
    }
    if visited
        .get(state)
        .is_some_and(|previous| *previous < path.len())
    {
        return false;
    }
    visited.insert(state.to_vec(), path.len());
    for index in 0..p.moves.len() {
        let (name, axis, perm) = &p.moves[index];
        if let Some(last) = last {
            let (last_name, last_axis, _) = &p.moves[last];
            let difference = *axis ^ *last_axis;
            if difference == 0 || (difference & 15 == 0 && name <= last_name) {
                continue;
            }
        }
        let next = perm.iter().map(|i| state[*i]).collect::<Vec<_>>();
        if next == state {
            continue;
        }
        path.push(index);
        if dfs(&next, remaining - 1, Some(index), path, visited, p) {
            return true;
        }
        path.pop();
    }
    false
}
fn find(
    goals: &[String],
    moves: &Value,
    algorithm: &str,
    maximum: usize,
) -> Result<Option<String>, SolveError> {
    let p = pattern(goals, moves, maximum.div_ceil(2))?;
    let state = apply(goals[0].as_bytes(), algorithm)?;
    for depth in 0..=maximum {
        let mut path = Vec::new();
        if dfs(&state, depth, None, &mut path, &mut HashMap::new(), &p) {
            return Ok(Some(
                path.into_iter()
                    .map(|i| p.moves[i].0.clone())
                    .collect::<Vec<_>>()
                    .join(" "),
            ));
        }
    }
    Ok(None)
}
pub fn solve(
    method: &str,
    algorithm: &str,
    options: &AssistOptions,
) -> Result<Vec<Solution>, SolveError> {
    cubegin_puzzle::parse(algorithm)?;
    let data = &RULES["stage-mask"];
    let moves = &data["MOVES"];
    if method == "333-general" || method == "block-222" {
        let mut answers = Vec::new();
        if method == "block-222" {
            let labels = data["BLOCK_222_TARGETS"]
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_str().unwrap().to_owned())
                .collect::<Vec<_>>();
            let all_goals = data["BLOCK_222_SOLVED_STATES"]
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_str().unwrap().to_owned())
                .collect::<Vec<_>>();
            for i in targets(&labels, options)? {
                let max = options.max_depth.unwrap_or(8);
                let goal = &all_goals[i];
                let p = pattern(&all_goals, moves, max.div_ceil(2))?;
                let state = apply(goal.as_bytes(), algorithm)?;
                let mut result = None;
                for depth in 0..=max {
                    let mut path = Vec::new();
                    if dfs(&state, depth, None, &mut path, &mut HashMap::new(), &p) {
                        result = Some(
                            path.into_iter()
                                .map(|i| p.moves[i].0.clone())
                                .collect::<Vec<_>>()
                                .join(" "),
                        );
                        break;
                    }
                }
                let a =
                    result.ok_or_else(|| fail(format!("no block solution for {}", labels[i])))?;
                answers.push(solution(method, &labels[i], &labels[i], "", &a));
            }
        } else {
            let defaults = vec!["Cross".to_owned()];
            for target in options.targets.as_ref().unwrap_or(&defaults) {
                let preset = data["GENERAL_PRESET_BY_LABEL"][target].as_str();
                let goal = if let Some(mask) = preset {
                    mask
                } else {
                    if target.len() != 54 || !target.chars().all(|c| "URFDLBHXYZ-".contains(c)) {
                        return Err(fail(format!("unknown mask target: {target}")));
                    }
                    target
                };
                let max = options.max_depth.unwrap_or(10);
                let a = find(&[goal.into()], moves, algorithm, max)?
                    .ok_or_else(|| fail(format!("no mask solution for {target}")))?;
                answers.push(solution(method, goal, target, "", &a));
            }
        }
        return Ok(answers);
    }
    let key = match method {
        "cfop-f2l" => "CFOP_F2L_META",
        "roux-s2" => "ROUX_S2_META",
        "petrus-s2" => "PETRUS_S2_META",
        "zz-f2l" => "ZZ_F2L_META",
        _ => "EO_DR_META",
    };
    let mut prior = String::new();
    let mut accumulated = 0u64;
    let mut answers = Vec::new();
    for stage in data[key].as_array().unwrap() {
        let maximum = options
            .max_depth
            .unwrap_or(stage["maxDepth"].as_u64().unwrap_or(10) as usize);
        let mut found = None;
        'stage: for depth in 0..=maximum {
            for (goal, bits) in stage["step"].as_object().unwrap() {
                let bits = bits.as_u64().unwrap();
                if bits | accumulated != bits {
                    continue;
                }
                let input = format!("{algorithm} {prior}");
                if let Some(a) = find(std::slice::from_ref(goal), &stage["move"], &input, depth)? {
                    found = Some((a, bits));
                    break 'stage;
                }
                if let Some(first) = stage["firstMoves"].as_array() {
                    for first in first {
                        let first = first.as_str().unwrap();
                        if let Some(a) = find(
                            std::slice::from_ref(goal),
                            &stage["move"],
                            &format!("{input} {first}"),
                            depth,
                        )? {
                            found = Some((format!("{first} {a}").trim().into(), bits));
                            break 'stage;
                        }
                    }
                }
            }
        }
        let (a, bits) = found.ok_or_else(|| {
            fail(format!(
                "no {method} solution for {} within {maximum}",
                stage["head"]
            ))
        })?;
        let label = stage["head"].as_str().unwrap();
        answers.push(solution(method, label, label, "", &a));
        prior.push(' ');
        prior.push_str(&a);
        accumulated |= bits;
    }
    Ok(answers)
}

/// Small-puzzle projected search; keep the exact move set and requested depth bound.
pub(super) fn custom_search(
    goals: Vec<Vec<u8>>,
    moves: Vec<(String, i32, Vec<usize>)>,
    initial: &[u8],
    maximum: usize,
    limit: usize,
) -> Vec<String> {
    let mut distances = HashMap::new();
    let mut queue = Vec::new();
    for goal in &goals {
        distances.insert(goal.clone(), 0);
        queue.push(goal.clone());
    }
    let mut cursor = 0;
    let mut complete = 0;
    'layers: for layer in 0..maximum.div_ceil(2) {
        let boundary = queue.len();
        while cursor < boundary {
            let state = queue[cursor].clone();
            for (_, _, perm) in &moves {
                let next = perm.iter().map(|i| state[*i]).collect::<Vec<_>>();
                if distances.contains_key(&next) {
                    continue;
                }
                if distances.len() >= 100_000 {
                    break 'layers;
                }
                distances.insert(next.clone(), layer + 1);
                queue.push(next);
            }
            cursor += 1;
        }
        complete = layer + 1;
        if queue.len() == boundary {
            complete = maximum;
            break;
        }
    }
    let p = Pattern {
        goals,
        moves,
        distances,
        unknown_bound: complete + 1,
    };
    let mut paths = Vec::new();
    let mut solutions = Vec::new();
    for depth in 0..=maximum {
        loop {
            let mut path = Vec::new();
            if !dfs_excluding(initial, depth, None, &mut path, &p, &paths) {
                break;
            }
            solutions.push(
                path.iter()
                    .map(|i| p.moves[*i].0.clone())
                    .collect::<Vec<_>>()
                    .join(" "),
            );
            paths.push(path);
            if paths.len() >= limit {
                return solutions;
            }
        }
    }
    solutions
}
fn dfs_excluding(
    state: &[u8],
    remaining: usize,
    last: Option<usize>,
    path: &mut Vec<usize>,
    p: &Pattern,
    excluded: &[Vec<usize>],
) -> bool {
    if p.distances.get(state).copied().unwrap_or(p.unknown_bound) > remaining {
        return false;
    }
    if remaining == 0 {
        return p.goals.iter().any(|goal| goal == state) && !excluded.contains(path);
    }
    for index in 0..p.moves.len() {
        let (name, axis, perm) = &p.moves[index];
        if let Some(last) = last {
            let (last_name, last_axis, _) = &p.moves[last];
            let difference = *axis ^ *last_axis;
            if difference == 0 || (difference & 15 == 0 && name <= last_name) {
                continue;
            }
        }
        let next = perm.iter().map(|i| state[*i]).collect::<Vec<_>>();
        if next == state {
            continue;
        }
        path.push(index);
        if dfs_excluding(&next, remaining - 1, Some(index), path, p, excluded) {
            return true;
        }
        path.pop();
    }
    false
}
