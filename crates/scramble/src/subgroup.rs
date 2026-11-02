//! Bounded BFS sampler matching the legacy SubgroupSolver's depth/state policy.
use cubegin_puzzle::{PuzzleError, events::EventState};
use cubegin_solver::SolveError;
use rand::Rng;
use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, LazyLock, Mutex},
};
static CACHE: LazyLock<Mutex<HashMap<String, Arc<Vec<String>>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
struct Node {
    state: Vec<u8>,
    parent: usize,
    mv: usize,
    depth: usize,
}
pub fn sample(
    event: &str,
    moves: &[String],
    max_depth: usize,
    max_states: usize,
    min_depth: usize,
    rng: &mut impl Rng,
) -> Result<String, SolveError> {
    let key = format!("{event}:{moves:?}:{max_depth}:{max_states}:{min_depth}");
    let cached = CACHE.lock().unwrap().get(&key).cloned();
    let candidates = if let Some(c) = cached {
        c
    } else {
        let initial = EventState::solved(event)?;
        let permutations = moves
            .iter()
            .map(|mv| {
                match &initial {
                    EventState::Cube(s) => tnoodle_backend::puzzle::CubeState::move_permutation(
                        s.size(),
                        &cubegin_puzzle::events::expand_cube_token(s.size(), mv)?,
                    ),
                    EventState::Minx(_) => {
                        tnoodle_backend::puzzle::MegaminxState::move_permutation(mv)
                    }
                    _ => unreachable!(),
                }
                .map_err(|e| SolveError::InvalidInput(PuzzleError::InvalidState(e.to_string())))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let state: Vec<u8> = match &initial {
            EventState::Cube(s) => (0..6 * s.size() * s.size())
                .map(|i| (i / (s.size() * s.size())) as u8)
                .collect(),
            EventState::Minx(_) => (0..132).map(|i| (i / 11) as u8).collect(),
            _ => unreachable!(),
        };
        let mut seen = HashSet::new();
        seen.insert(state.clone());
        let mut nodes = vec![Node {
            state,
            parent: 0,
            mv: 0,
            depth: 0,
        }];
        let mut cursor = 0;
        'outer: while cursor < nodes.len() {
            let depth = nodes[cursor].depth;
            if depth == max_depth {
                cursor += 1;
                continue;
            }
            for (mi, perm) in permutations.iter().enumerate() {
                let state = perm
                    .iter()
                    .map(|i| nodes[cursor].state[*i])
                    .collect::<Vec<_>>();
                if !seen.insert(state.clone()) {
                    continue;
                }
                nodes.push(Node {
                    state,
                    parent: cursor,
                    mv: mi,
                    depth: depth + 1,
                });
                if nodes.len() >= max_states {
                    break 'outer;
                }
            }
            cursor += 1;
        }
        let mut candidates = Vec::new();
        for i in 0..nodes.len() {
            if nodes[i].depth < min_depth {
                continue;
            }
            let mut path = Vec::new();
            let mut j = i;
            while j != 0 {
                path.push(moves[nodes[j].mv].clone());
                j = nodes[j].parent;
            }
            path.reverse();
            candidates.push(path.join(" "));
        }
        if candidates.is_empty() {
            return Err(SolveError::Backend(
                "subgroup has no candidate at requested depth".into(),
            ));
        }
        let candidates = Arc::new(candidates);
        CACHE.lock().unwrap().insert(key, candidates.clone());
        candidates
    };
    Ok(candidates[rng.gen_range(0..candidates.len())].clone())
}
