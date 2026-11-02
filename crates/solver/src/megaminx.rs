//! LSLL coordinate solver ported from legacy megaminx-lsll-solver.ts (79a1e4c).
use crate::SolveError;
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, sync::LazyLock};
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LsllState {
    pub edge_permutation: [u8; 6],
    pub edge_orientation: [u8; 6],
    pub corner_permutation: [u8; 6],
    pub corner_orientation: [u8; 6],
}
struct Tables {
    permutations: Vec<[u8; 6]>,
    indices: HashMap<[u8; 6], usize>,
    edge_moves: Vec<[usize; 3]>,
    corner_moves: Vec<[usize; 3]>,
    edge_pruning: Vec<i8>,
    corner_pruning: Vec<i8>,
}
static TABLES: LazyLock<Tables> = LazyLock::new(build);
fn pack(v: &[u8; 6], modulus: usize) -> usize {
    v[..5].iter().fold(0, |c, v| c * modulus + usize::from(*v))
}
fn unpack(mut value: usize, modulus: usize) -> [u8; 6] {
    let mut v = [0; 6];
    let mut sum = 0;
    for i in (0..5).rev() {
        v[i] = (value % modulus) as u8;
        sum += usize::from(v[i]);
        value /= modulus;
    }
    v[5] = ((modulus - sum % modulus) % modulus) as u8;
    v
}
fn cycle(v: &mut [u8; 6], positions: &[usize; 5], offsets: Option<[u8; 5]>, modulus: u8) {
    let old = positions.map(|i| v[i]);
    for i in 0..5 {
        let target = (i + 1) % 5;
        v[positions[target]] = if let Some(offset) = offsets {
            (old[i] + modulus - offset[i] + offset[target]) % modulus
        } else {
            old[i]
        };
    }
}
fn move_coord(
    value: usize,
    axis: usize,
    modulus: usize,
    permutations: &[[u8; 6]],
    indices: &HashMap<[u8; 6], usize>,
) -> usize {
    let count = modulus.pow(5);
    let mut p = permutations[value / count];
    let mut o = unpack(value % count, modulus);
    let (positions, offsets) = if modulus == 2 {
        match axis {
            0 => ([0, 1, 2, 3, 4], None),
            1 => ([0, 1, 2, 3, 5], None),
            _ => ([1, 2, 3, 4, 5], Some([0, 0, 0, 0, 1])),
        }
    } else {
        match axis {
            0 => ([0, 1, 2, 3, 4], None),
            1 => ([0, 5, 1, 2, 3], Some([2, 0, 0, 0, 0])),
            _ => ([0, 2, 3, 4, 5], Some([1, 0, 0, 0, 1])),
        }
    };
    cycle(&mut p, &positions, None, modulus as u8);
    cycle(&mut o, &positions, offsets, modulus as u8);
    indices[&p] * count + pack(&o, modulus)
}
fn pruning(moves: &[[usize; 3]]) -> Vec<i8> {
    let mut d = vec![-1; moves.len()];
    d[0] = 0;
    let mut queue = vec![0];
    let mut cursor = 0;
    while cursor < queue.len() {
        let state = queue[cursor];
        cursor += 1;
        for axis in [0, 1, 2] {
            let mut next = state;
            for _ in 1..5 {
                next = moves[next][axis];
                if d[next] < 0 {
                    d[next] = d[state] + 1;
                    queue.push(next);
                }
            }
        }
    }
    d
}
fn build() -> Tables {
    let permutations: Vec<[u8; 6]> =
        serde_json::from_str(include_str!("../data/megaminx-permutations.json")).unwrap();
    let indices = permutations
        .iter()
        .enumerate()
        .map(|(i, p)| (*p, i))
        .collect::<HashMap<_, _>>();
    let edge_moves = (0..360 * 32)
        .map(|i| std::array::from_fn(|axis| move_coord(i, axis, 2, &permutations, &indices)))
        .collect::<Vec<_>>();
    let corner_moves = (0..360 * 243)
        .map(|i| std::array::from_fn(|axis| move_coord(i, axis, 3, &permutations, &indices)))
        .collect::<Vec<_>>();
    let edge_pruning = pruning(&edge_moves);
    let corner_pruning = pruning(&corner_moves);
    Tables {
        permutations,
        indices,
        edge_moves,
        corner_moves,
        edge_pruning,
        corner_pruning,
    }
}
fn coordinates(s: &LsllState, t: &Tables) -> Result<(usize, usize), SolveError> {
    let fail = || SolveError::Backend("invalid Megaminx LSLL coordinates".into());
    let ep = *t.indices.get(&s.edge_permutation).ok_or_else(fail)?;
    let cp = *t.indices.get(&s.corner_permutation).ok_or_else(fail)?;
    if s.edge_orientation.iter().any(|v| *v > 1)
        || s.corner_orientation.iter().any(|v| *v > 2)
        || s.edge_orientation.iter().sum::<u8>() % 2 != 0
        || s.corner_orientation.iter().sum::<u8>() % 3 != 0
    {
        return Err(fail());
    }
    Ok((
        ep * 32 + pack(&s.edge_orientation, 2),
        cp * 243 + pack(&s.corner_orientation, 3),
    ))
}
fn search(
    e: usize,
    c: usize,
    remaining: usize,
    last: usize,
    path: &mut Vec<(usize, usize)>,
    t: &Tables,
) -> bool {
    if remaining == 0 {
        return e == 0 && c == 0;
    }
    if t.edge_pruning[e] > remaining as i8 || t.corner_pruning[c] > remaining as i8 {
        return false;
    }
    for axis in 0..3 {
        if axis == last {
            continue;
        }
        let (mut ne, mut nc) = (e, c);
        for power in 1..5 {
            ne = t.edge_moves[ne][axis];
            nc = t.corner_moves[nc][axis];
            path.push((axis, power));
            if search(ne, nc, remaining - 1, axis, path, t) {
                return true;
            }
            path.pop();
        }
    }
    false
}
pub fn scramble(state: &LsllState) -> Result<String, SolveError> {
    let t = &*TABLES;
    let (e, c) = coordinates(state, t)?;
    let minimum = t.edge_pruning[e].max(t.corner_pruning[c]);
    if minimum < 0 {
        return Err(SolveError::Backend(
            "unreachable Megaminx LSLL state".into(),
        ));
    }
    let mut path = Vec::new();
    for depth in minimum as usize..=20 {
        if search(e, c, depth, 3, &mut path, t) {
            return Ok(path
                .into_iter()
                .rev()
                .map(|(axis, power)| format_macro(axis, 5 - power))
                .collect::<Vec<_>>()
                .join(" "));
        }
    }
    Err(SolveError::Backend(
        "Megaminx LSLL search exceeded depth 20".into(),
    ))
}
fn format_macro(axis: usize, power: usize) -> String {
    let suffix = ["", "", "2", "2'", "'"][power];
    match axis {
        0 => format!("U{suffix}"),
        1 => format!("R U{suffix} R'"),
        _ => format!("F' U{suffix} F"),
    }
}
pub fn state_from_algorithm(algorithm: &str) -> Result<LsllState, SolveError> {
    let tokens = algorithm.split_whitespace().collect::<Vec<_>>();
    let (mut e, mut c, mut i) = (0, 0, 0);
    let t = &*TABLES;
    while i < tokens.len() {
        let (axis, token, step) = if tokens[i].starts_with('U') {
            (0, tokens[i], 1)
        } else if i + 2 < tokens.len() && tokens[i] == "R" && tokens[i + 2] == "R'" {
            (1, tokens[i + 1], 3)
        } else if i + 2 < tokens.len() && tokens[i] == "F'" && tokens[i + 2] == "F" {
            (2, tokens[i + 1], 3)
        } else {
            return Err(SolveError::Backend(
                "unsupported Megaminx LSLL macro".into(),
            ));
        };
        let power = match token {
            "U" => 1,
            "U2" => 2,
            "U2'" => 3,
            "U'" => 4,
            _ => return Err(SolveError::Backend("invalid Megaminx LSLL U turn".into())),
        };
        for _ in 0..power {
            e = t.edge_moves[e][axis];
            c = t.corner_moves[c][axis];
        }
        i += step;
    }
    Ok(LsllState {
        edge_permutation: t.permutations[e / 32],
        edge_orientation: unpack(e % 32, 2),
        corner_permutation: t.permutations[c / 243],
        corner_orientation: unpack(c % 243, 3),
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn coordinate_solution_replay() {
        let s = state_from_algorithm("R U2 R' F' U F U'").unwrap();
        let a = scramble(&s).unwrap();
        assert_eq!(
            serde_json::to_value(state_from_algorithm(&a).unwrap()).unwrap(),
            serde_json::to_value(s).unwrap()
        );
    }
}
