use crate::{PuzzleError, SolveError};
pub use cubegin_puzzle::events::{EventInfo, catalog, inverse_event};
use cubegin_puzzle::events::{EventState, tokenize};
pub use cubegin_scramble::events::{EventScramble, generate_event, generate_multi_blind};
pub use cubegin_solver::events::solve_event;
use serde::Serialize;
#[derive(Debug, Serialize)]
pub struct EventSnapshot {
    pub event_id: String,
    pub state: serde_json::Value,
    pub solved: bool,
    pub svg: String,
}
pub fn evaluate_event(event: &str, algorithm: &str) -> Result<EventSnapshot, PuzzleError> {
    let state = EventState::solved(event)?.apply(algorithm)?;
    Ok(EventSnapshot {
        event_id: event.into(),
        state: state.data(),
        solved: state.is_solved(),
        svg: cubegin_diagram::trim_event_svg(state.svg(event)?),
    })
}
#[derive(Debug, Serialize)]
pub struct EventStep {
    pub notation: String,
    pub before: serde_json::Value,
    pub after: serde_json::Value,
    pub duration_ms: u32,
}
pub fn timeline_event(event: &str, algorithm: &str) -> Result<Vec<EventStep>, PuzzleError> {
    let tokens = tokenize(algorithm)?;
    if tokens.len() > 1000 {
        return Err(PuzzleError::AlgorithmTooLong);
    }
    let mut state = EventState::solved(event)?;
    let mut steps = Vec::new();
    for token in tokens {
        let before = state.data();
        state = state.apply(&token)?;
        steps.push(EventStep {
            notation: token,
            before,
            after: state.data(),
            duration_ms: 520,
        });
    }
    Ok(steps)
}
#[allow(dead_code)]
fn _error_contract(_: SolveError) {}

pub use cubegin_scramble::training::{
    Orientation, TrainingOptions, TrainingScramble, cases, generate_training, type_catalog,
};
pub use cubegin_solver::assist::{AssistOptions, AssistResult, METHODS, solve_assist};

pub use cubegin_playback::player::{player_frame, player_svg, player_timeline};
pub use cubegin_solver::fmc::validate_fmc;

/// Generates a bounded batch without repeating normalized puzzle states.
pub fn generate_batch(
    id: &str,
    seed: u32,
    count: u32,
    options: &TrainingOptions,
) -> Result<Vec<serde_json::Value>, SolveError> {
    if count == 0 || count > 100 {
        return Err(PuzzleError::InvalidState("batch count must be 1..100".into()).into());
    }
    let catalog = type_catalog();
    let kind = &catalog[id]["kind"];
    if kind.is_null() {
        return Err(PuzzleError::InvalidState("unknown scramble type".into()).into());
    }
    let mut seen = std::collections::HashSet::new();
    let mut output = Vec::new();
    for attempt in 0..count * 100 {
        let next = seed.wrapping_add(attempt);
        let (value, event, algorithm) = if kind == "official" {
            let r = generate_event(id, next)?;
            let event = r.event_id.clone();
            let algorithm = r.algorithm.clone();
            (serde_json::to_value(r).unwrap(), event, algorithm)
        } else {
            let r = generate_training(id, next, options)?;
            let event = r.event_id.clone();
            let algorithm = r.algorithm.clone();
            (serde_json::to_value(r).unwrap(), event, algorithm)
        };
        let key = EventState::solved(&event)?
            .apply(&algorithm)?
            .normalized_key();
        if seen.insert(key) {
            output.push(value);
        }
        if output.len() == count as usize {
            return Ok(output);
        }
    }
    Err(PuzzleError::InvalidState("not enough distinct states for requested batch".into()).into())
}
