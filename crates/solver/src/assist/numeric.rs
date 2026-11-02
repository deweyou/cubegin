use super::{AssistOptions, RULES, Solution, fail, solution, targets};
use crate::SolveError;
use serde::Deserialize;
use std::{collections::HashMap, sync::LazyLock};
#[derive(Deserialize)]
struct Descriptor {
    offset: usize,
    shape: Vec<usize>,
}
static DESCRIPTORS: LazyLock<HashMap<String, Descriptor>> =
    LazyLock::new(|| serde_json::from_str(include_str!("../../data/assist-tables.json")).unwrap());
static DATA: &[u8] = include_bytes!("../../data/assist-tables.bin");
fn table(name: &str, indices: &[usize]) -> usize {
    let d = &DESCRIPTORS[name];
    let offset = indices
        .iter()
        .zip(&d.shape)
        .fold(0, |offset, (index, size)| offset * size + index);
    let at = (d.offset + offset) * 4;
    i32::from_le_bytes(DATA[at..at + 4].try_into().unwrap()) as usize
}
fn distance(name: &str, indices: &[usize]) -> i32 {
    table(name, indices) as i32
}
const TURNS: &str = "UDLRFB";
#[derive(Clone, Copy)]
enum Kind {
    Cross,
    XCross(usize),
    Eofc,
    Eoline,
    Petrus,
    Roux,
}
#[derive(Clone, Copy)]
struct State([usize; 4]);
impl Kind {
    fn apply(self, s: State, m: usize) -> State {
        let v = s.0;
        State(match self {
            Self::Cross => [
                table("cross.epm", &[v[0], m]),
                table("cross.eom", &[v[1], m]),
                0,
                0,
            ],
            Self::XCross(_) => [
                table("cross.epm", &[v[0], m]),
                table("cross.eom", &[v[1], m]),
                table("cross.fcm", &[v[2], m]),
                table("cross.fem", &[v[3], m]),
            ],
            Self::Eofc => [
                table("cross.epm", &[v[0], m]),
                table("cross.eom", &[v[1], m]),
                table("cross.eom", &[v[2], m]),
                0,
            ],
            Self::Eoline => [
                table("eoline.epm", &[v[0], m]),
                table("eoline.eom", &[v[1], m]),
                0,
                0,
            ],
            Self::Petrus => [
                table("petrus.epm", &[v[0], m]),
                table("petrus.eom", &[v[1], m]),
                table("petrus.com", &[v[2], m]),
                0,
            ],
            Self::Roux => [
                table("petrus.epm", &[v[0], m]),
                table("petrus.eom", &[v[1], m]),
                table("roux.cpm", &[v[2], m]),
                table("roux.com", &[v[3], m]),
            ],
        })
    }
    fn solved(self, s: State) -> bool {
        let v = s.0;
        match self {
            Self::Cross => v[0] == 1656 && v[1] == 1104,
            Self::XCross(slot) => v == [1656, 1104, (slot + 4) * 3, slot * 2],
            Self::Eofc => v[0] == 1656 && v[1] == 1104 && v[2] & 15 == 0,
            Self::Eoline => v[0] == 106 && v[1] == 0,
            Self::Petrus => v[0] == 102 && v[1] == 136 && v[2] == 12,
            Self::Roux => v == [72, 96, 50, 225],
        }
    }
    fn pruning(self, s: State) -> i32 {
        let v = s.0;
        match self {
            Self::Cross => distance("cross.epd", &[v[0]]).max(distance("cross.eod", &[v[1]])),
            Self::XCross(slot) => distance("cross.epd", &[v[0]])
                .max(distance("cross.eod", &[v[1]]))
                .max(distance("cross.fecd", &[slot, v[3] * 24 + v[2]])),
            Self::Eofc => distance("cross.epd", &[v[0]])
                .max(distance("cross.eod", &[v[1]]))
                .max(distance("cross.eofd", &[v[2]])),
            Self::Eoline => distance("eoline.epd", &[v[0]]).max(distance("eoline.eod", &[v[1]])),
            Self::Petrus => distance("petrus.epd", &[v[0]]).max(distance("petrus.eod", &[v[1]])),
            Self::Roux => distance("roux.ed", &[(v[0] << 3) | (v[1] & 7)])
                .max(distance("roux.cd", &[v[2] * 9 + v[3] % 9])),
        }
    }
}
fn dfs(kind: Kind, state: State, depth: usize, last: usize, path: &mut Vec<usize>) -> bool {
    if depth == 0 {
        return kind.solved(state);
    }
    if kind.pruning(state) > depth as i32 {
        return false;
    }
    for mv in 0..6 {
        if mv == last {
            continue;
        }
        let mut next = state;
        for turn in 0..3 {
            next = kind.apply(next, mv);
            path.push(mv * 3 + turn);
            if dfs(kind, next, depth - 1, mv, path) {
                return true;
            }
            path.pop();
        }
    }
    false
}
fn initial(kind: Kind, algorithm: &str, move_map: &str, state: State) -> Result<State, SolveError> {
    let mut state = state;
    for turn in cubegin_puzzle::parse(algorithm)? {
        let mv = move_map
            .chars()
            .position(|f| f == turn.face())
            .ok_or_else(|| fail("invalid face mapping"))?;
        for _ in 0..turn.turns() {
            state = kind.apply(state, mv);
        }
    }
    Ok(state)
}
fn format_path(path: &[usize], faces: &str) -> String {
    path.iter()
        .map(|m| {
            format!(
                "{}{}",
                faces.as_bytes()[m / 3] as char,
                ["", "2", "'"][m % 3]
            )
        })
        .collect::<Vec<_>>()
        .join(" ")
}
fn values(family: &str, name: &str) -> Vec<String> {
    RULES[family][name]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap().into())
        .collect()
}
pub fn solve(
    method: &str,
    algorithm: &str,
    options: &AssistOptions,
) -> Result<Vec<Solution>, SolveError> {
    cubegin_puzzle::parse(algorithm)?;
    let (family, target_key, limit) = match method {
        "cross" => ("cross", "CROSS_TARGETS", 8),
        "xcross" => ("cross", "CROSS_TARGETS", 10),
        "eofc" => ("cross", "EOFC_TARGETS", 12),
        "eoline" => ("eoline", "EOLINE_TARGETS", 9),
        "petrus-s1" => ("petrus", "PETRUS_TARGETS", 8),
        _ => ("roux", "ROUX_TARGETS", 9),
    };
    let labels = values(family, target_key);
    let max_depth = options.max_depth.unwrap_or(limit);
    let mut results = Vec::new();
    for index in targets(&labels, options)? {
        let mut candidates = Vec::new();
        match method {
            "cross" | "xcross" => {
                let map = RULES["cross"]["CROSS_MOVE_STRINGS"][0][index]
                    .as_str()
                    .unwrap();
                for slot in 0..if method == "cross" { 1 } else { 4 } {
                    let kind = if method == "cross" {
                        Kind::Cross
                    } else {
                        Kind::XCross(slot)
                    };
                    let s = State([1656, 1104, (slot + 4) * 3, slot * 2]);
                    candidates.push((
                        kind,
                        initial(kind, algorithm, map, s)?,
                        RULES["cross"]["CROSS_ROTATIONS"][0][index]
                            .as_str()
                            .unwrap()
                            .to_owned(),
                        TURNS.to_owned(),
                    ));
                }
            }
            "eofc" | "eoline" => {
                let map = RULES["cross"]["EO_LINE_MOVE_STRINGS"][index]
                    .as_str()
                    .unwrap();
                let kind = if method == "eofc" {
                    Kind::Eofc
                } else {
                    Kind::Eoline
                };
                let s = if method == "eofc" {
                    State([1656, 1104, 0, 0])
                } else {
                    State([106, 0, 0, 0])
                };
                candidates.push((
                    kind,
                    initial(kind, algorithm, map, s)?,
                    RULES["cross"]["EO_LINE_ROTATIONS"][index]
                        .as_str()
                        .unwrap()
                        .to_owned(),
                    TURNS.to_owned(),
                ));
            }
            "petrus-s1" => {
                let map = RULES["petrus"]["PETRUS_MOVE_STRINGS"][index]
                    .as_str()
                    .unwrap();
                candidates.push((
                    Kind::Petrus,
                    initial(Kind::Petrus, algorithm, map, State([102, 136, 12, 0]))?,
                    String::new(),
                    map.into(),
                ));
            }
            _ => {
                let slots = RULES["roux"]["ORIENTATION_INDEXES"][index % 2]
                    .as_array()
                    .unwrap();
                for ori in 0..4 {
                    let i = slots[ori].as_u64().unwrap() as usize;
                    let v = [
                        RULES["roux"]["SOLVED_EP"][i].as_u64().unwrap() as usize,
                        RULES["roux"]["SOLVED_EO"][i].as_u64().unwrap() as usize,
                        RULES["roux"]["SOLVED_CP"][i].as_u64().unwrap() as usize,
                        RULES["roux"]["SOLVED_CO"][i].as_u64().unwrap() as usize,
                    ];
                    let map = RULES["roux"]["ROUX_MOVE_STRINGS"][index / 2][ori]
                        .as_str()
                        .unwrap();
                    let rotation = [
                        RULES["roux"]["ROUX_ROTATIONS"][index / 2].as_str().unwrap(),
                        RULES["roux"]["ROUX_ORIENTATION_ROTATIONS"][ori]
                            .as_str()
                            .unwrap(),
                    ]
                    .into_iter()
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>()
                    .join(" ");
                    candidates.push((
                        Kind::Roux,
                        initial(Kind::Roux, algorithm, map, State(v))?,
                        rotation,
                        TURNS.into(),
                    ));
                }
            }
        }
        let mut found = None;
        'search: for depth in 0..=max_depth {
            for (kind, state, rotation, faces) in &candidates {
                let mut path = Vec::new();
                if dfs(*kind, *state, depth, 6, &mut path) {
                    found = Some((format_path(&path, faces), rotation.clone()));
                    break 'search;
                }
            }
        }
        let (a, rotation) = found.ok_or_else(|| {
            fail(format!(
                "no {method} solution for {} within {max_depth}",
                labels[index]
            ))
        })?;
        let label = if method == "cross" {
            format!("Cross({})", labels[index])
        } else if method == "xcross" {
            format!("XCross({})", labels[index])
        } else {
            labels[index].clone()
        };
        results.push(solution(method, &labels[index], &label, &rotation, &a));
    }
    Ok(results)
}
