use cubegin_puzzle::{
    PuzzleError,
    events::{EventState, scrambler},
};
use serde::Serialize;
use tnoodle_backend::java::JavaRandom;
#[derive(Debug, Serialize)]
pub struct EventScramble {
    pub event_id: String,
    pub algorithm: String,
    pub seed: u32,
    pub state: serde_json::Value,
}
/// Seeded diagnostic generator. State generation policy is inherited from TNoodle;
/// this is not certification of the application for competition use.
pub fn generate_event(event: &str, seed: u32) -> Result<EventScramble, PuzzleError> {
    if event == "333mbld" {
        return Err(PuzzleError::InvalidState(
            "multi-blind requires a batch cube count; use generate_multi_blind".into(),
        ));
    }
    let generator = scrambler(event)?;
    let mut rng = JavaRandom::new(i64::from(seed));
    let algorithm = generator.generate_wca_scramble(&mut rng);
    let state = EventState::solved(event)?.apply(&algorithm)?.data();
    Ok(EventScramble {
        event_id: event.into(),
        algorithm,
        seed,
        state,
    })
}
pub fn generate_multi_blind(seed: u32, count: u32) -> Result<Vec<EventScramble>, PuzzleError> {
    if !(2..=100).contains(&count) {
        return Err(PuzzleError::InvalidState(
            "multi-blind count must be 2..100".into(),
        ));
    }
    (0..count)
        .map(|i| {
            let mut item = generate_event("333bld", seed.wrapping_add(i))?;
            item.event_id = "333mbld".into();
            Ok(item)
        })
        .collect()
}
