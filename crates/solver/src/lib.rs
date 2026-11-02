pub mod assist;
pub mod events;
pub mod megaminx;
use cubegin_puzzle::{Cube, PuzzleError, format, parse};
use thiserror::Error;
#[derive(Debug, Error)]
pub enum SolveError {
    #[error(transparent)]
    InvalidInput(#[from] PuzzleError),
    #[error("solver backend failed: {0}")]
    Backend(String),
    #[error("solver returned a formula that does not restore the input")]
    InvalidSolution,
}
/// Solves any legal fixed-center 3x3 state. Synchronous and CPU-bound; callers own scheduling.
/// The backend has no cooperative cancellation; this API makes no deadline guarantee.
pub fn solve(facelets: &str) -> Result<String, SolveError> {
    let cube = Cube::from_facelets(facelets)?;
    if cube.is_solved() {
        return Ok(String::new());
    }
    let output =
        tnoodle_backend::min2phase::Search::new().solution(&cube.facelets(), 21, 100_000, 0, 0);
    if output.starts_with("Error") {
        return Err(SolveError::Backend(output));
    }
    let solution = format(&parse(&output)?);
    if !cube.apply(&solution)?.is_solved() {
        return Err(SolveError::InvalidSolution);
    }
    Ok(solution)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn replay_solutions() {
        for alg in ["", "R", "R U R' U'", "F2 U L2 B' R D2 F U2 R' B2 L D'"] {
            let cube = Cube::default().apply(alg).unwrap();
            assert!(
                cube.apply(&solve(&cube.facelets()).unwrap())
                    .unwrap()
                    .is_solved()
            );
        }
    }
    #[test]
    fn invalid_input_is_error() {
        assert!(solve("garbage").is_err());
    }
}
pub mod fmc;
