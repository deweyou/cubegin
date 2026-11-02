use cubegin_puzzle::{Cube, FACES, NORMALS, PuzzleError, parse};
use serde::Serialize;
#[derive(Debug, Serialize)]
pub struct Step {
    pub notation: String,
    pub axis: [i8; 3],
    pub angle_radians: f64,
    pub duration_ms: u32,
    pub before: String,
    pub after: String,
}
/// Renderer-independent step boundaries. Renderers interpolate locally and select pieces
/// whose position dot axis is +1. No frame loop or camera belongs in this crate.
pub fn timeline(cube: &Cube, algorithm: &str) -> Result<Vec<Step>, PuzzleError> {
    let mut state = cube.clone();
    let mut steps = Vec::new();
    for turn in parse(algorithm)? {
        let before = state.facelets();
        state.apply_move(turn);
        let quarters = if turn.turns() == 3 {
            -1.0
        } else {
            turn.turns() as f64
        };
        steps.push(Step {
            notation: turn.to_string(),
            axis: NORMALS[FACES.iter().position(|f| *f == turn.face() as u8).unwrap()],
            angle_radians: -quarters * std::f64::consts::FRAC_PI_2,
            duration_ms: if turn.turns() == 2 { 754 } else { 520 },
            before,
            after: state.facelets(),
        });
    }
    Ok(steps)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn timeline_matches_state_transitions() {
        let steps = timeline(&Cube::default(), "R U2 F'").unwrap();
        assert_eq!(steps.len(), 3);
        assert_eq!(steps[0].before, Cube::default().facelets());
        for pair in steps.windows(2) {
            assert_eq!(pair[0].after, pair[1].before);
        }
        assert_eq!(
            steps[2].after,
            Cube::default().apply("R U2 F'").unwrap().facelets()
        );
        assert!(steps[2].angle_radians > 0.0);
    }
}

pub mod player;
