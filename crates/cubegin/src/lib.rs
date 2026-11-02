pub mod events;
pub use cubegin_playback::{Step, timeline};
pub use cubegin_puzzle::{Cube, PuzzleError, SOLVED, inverse};
pub use cubegin_solver::{SolveError, solve};
use serde::Serialize;
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
#[derive(Debug, Serialize)]
pub struct Snapshot {
    pub facelets: String,
    pub solved: bool,
    pub svg: String,
}
#[derive(Debug, Serialize)]
pub struct Scramble {
    pub algorithm: String,
    pub facelets: String,
    pub seed: u32,
}
pub fn evaluate(algorithm: &str) -> Result<Snapshot, PuzzleError> {
    let cube = Cube::default().apply(algorithm)?;
    Ok(Snapshot {
        facelets: cube.facelets(),
        solved: cube.is_solved(),
        svg: cubegin_diagram::render(&cube),
    })
}
pub fn render(facelets: &str) -> Result<String, PuzzleError> {
    Ok(cubegin_diagram::render(&Cube::from_facelets(facelets)?))
}
pub fn scramble(seed: u32) -> Result<Scramble, SolveError> {
    let (algorithm, facelets) = cubegin_scramble::generate(seed)?;
    Ok(Scramble {
        algorithm,
        facelets,
        seed,
    })
}
