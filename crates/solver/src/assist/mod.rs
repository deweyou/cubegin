//! Auxiliary search APIs. Coordinates, masks and move semantics follow legacy 79a1e4c.
mod mask;
mod numeric;
mod small;
use crate::SolveError;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::LazyLock;
static RULES: LazyLock<Value> =
    LazyLock::new(|| serde_json::from_str(include_str!("../../data/assist-rules.json")).unwrap());
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AssistOptions {
    pub targets: Option<Vec<String>>,
    pub max_depth: Option<usize>,
    pub max_solutions_per_target: Option<usize>,
}
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Solution {
    pub method: String,
    pub target: String,
    pub target_label: String,
    pub setup_rotation: String,
    pub solution: String,
    pub depth: usize,
    pub metric: Metric,
}
#[derive(Debug, Serialize, Deserialize)]
pub struct Metric {
    pub ftm: usize,
    pub qtm: usize,
}
#[derive(Debug, Serialize, Deserialize)]
pub struct AssistResult {
    pub method: String,
    pub scramble: String,
    pub solutions: Vec<Solution>,
}
pub const METHODS: &[(&str, &str)] = &[
    ("333", "cross"),
    ("333", "xcross"),
    ("333", "eoline"),
    ("333", "eofc"),
    ("333", "roux-s1"),
    ("333", "roux-s2"),
    ("333", "petrus-s1"),
    ("333", "petrus-s2"),
    ("333", "cfop-f2l"),
    ("333", "zz-f2l"),
    ("333", "block-222"),
    ("333", "eo-dr"),
    ("333", "333-two-phase"),
    ("333", "333-general"),
    ("222", "222-face"),
    ("222", "222-layer"),
    ("sq1", "sq1-shape-ftm"),
    ("sq1", "sq1-shape-twist"),
    ("pyram", "pyraminx-v"),
    ("skewb", "skewb-face"),
];
pub fn solve_assist(
    event: &str,
    methods: &[String],
    scramble: &str,
    options: &AssistOptions,
) -> Result<Vec<AssistResult>, SolveError> {
    if options.max_depth.is_some_and(|d| d > 30) || options.max_solutions_per_target == Some(0) {
        return Err(fail("invalid search limits"));
    }
    for method in methods {
        if !METHODS.contains(&(event, method.as_str())) {
            return Err(fail(format!("unsupported event/method: {event}/{method}")));
        }
    }
    methods
        .iter()
        .map(|method| {
            let solutions = match method.as_str() {
                "cross" | "xcross" | "eoline" | "eofc" | "roux-s1" | "petrus-s1" => {
                    numeric::solve(method, scramble, options)?
                }
                "cfop-f2l" | "roux-s2" | "petrus-s2" | "zz-f2l" | "eo-dr" | "block-222"
                | "333-general" => mask::solve(method, scramble, options)?,
                "333-two-phase" => {
                    let cube = cubegin_puzzle::Cube::default().apply(scramble)?;
                    let output = tnoodle_backend::min2phase::Search::new().solution(
                        &cube.facelets(),
                        options.max_depth.unwrap_or(30) as i32,
                        100_000,
                        0,
                        0,
                    );
                    if output.starts_with("Error") {
                        return Err(fail(output));
                    }
                    vec![solution(method, "333", "3x3x3 TwoPhase", "", output.trim())]
                }
                _ => small::solve(event, method, scramble, options)?,
            };
            Ok(AssistResult {
                method: method.clone(),
                scramble: scramble.into(),
                solutions,
            })
        })
        .collect()
}
fn fail(reason: impl Into<String>) -> SolveError {
    SolveError::Backend(reason.into())
}
fn solution(method: &str, target: &str, label: &str, rotation: &str, algorithm: &str) -> Solution {
    let tokens = algorithm
        .split_whitespace()
        .filter(|t| !t.starts_with(['x', 'y', 'z']))
        .collect::<Vec<_>>();
    Solution {
        method: method.into(),
        target: target.into(),
        target_label: label.into(),
        setup_rotation: rotation.into(),
        solution: algorithm.into(),
        depth: algorithm.split_whitespace().count(),
        metric: Metric {
            ftm: tokens.len(),
            qtm: tokens
                .iter()
                .map(|t| if t.ends_with('2') { 2 } else { 1 })
                .sum(),
        },
    }
}
fn targets(default: &[String], options: &AssistOptions) -> Result<Vec<usize>, SolveError> {
    options.targets.as_ref().map_or_else(
        || Ok((0..default.len()).collect()),
        |ids| {
            ids.iter()
                .map(|id| {
                    default
                        .iter()
                        .position(|v| v == id)
                        .ok_or_else(|| fail(format!("unknown target: {id}")))
                })
                .collect()
        },
    )
}
