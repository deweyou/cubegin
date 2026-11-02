use crate::SolveError;
use cubegin_puzzle::events::{EventState, base_event, inverse_event};
use tnoodle_backend::PuzzleState;
/// Full restore from a formula, matching the legacy facade's input contract.
/// Search output is replayed against puzzle state, never accepted on faith.
pub fn solve_event(event: &str, algorithm: &str) -> Result<String, SolveError> {
    let state = EventState::solved(event)?.apply(algorithm)?;
    if state.is_solved() {
        return Ok(String::new());
    }
    let base = base_event(event)?;
    let solution = match (&state, base) {
        (EventState::Cube(cube), "222") => cube.solve_in(20),
        (EventState::Cube(cube), "333") => {
            Some(crate::solve(&fixed_centers(&cube.to_face_cube()))?)
        }
        (EventState::Cube(cube), "444") => {
            let mut search = tnoodle_backend::threephase::Search::new();
            search.inverse_solution = false;
            search.with_rotation = true;
            Some(search.solution(&cube.to_face_cube()))
        }
        (EventState::Pyram(s), _) => s.solve_in(20),
        (EventState::Skewb(s), _) => s.solve_in(12),
        (EventState::Sq1(s), _) => s.solve_in(31),
        (EventState::Fto(_), _) => {
            let cubie = tnoodle_backend::fto3phase::from_alg(algorithm);
            let generator = tnoodle_backend::fto3phase::Search::new().solution(&cubie);
            Some(inverse_event(event, &generator)?)
        }
        (EventState::Clock(_), _) => Some(inverse_event(event, algorithm)?),
        _ => {
            return Err(SolveError::Backend(format!(
                "no full solver existed for event {event}"
            )));
        }
    }
    .ok_or_else(|| SolveError::Backend(format!("no solution found for {event}")))?;
    if !state.apply(&solution)?.is_solved() {
        return Err(SolveError::InvalidSolution);
    }
    Ok(solution.trim().into())
}

fn fixed_centers(facelets: &str) -> String {
    let bytes = facelets.as_bytes();
    let centers: [u8; 6] = std::array::from_fn(|i| bytes[i * 9 + 4]);
    bytes
        .iter()
        .map(|color| "URFDLB".as_bytes()[centers.iter().position(|c| c == color).unwrap()] as char)
        .collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn small_event_full_solvers() {
        for (event, algorithm) in [
            ("222", "R U F2 R'"),
            ("333", "R U R' U'"),
            ("pyram", "U L' R b"),
            ("skewb", "R U' L B"),
            ("clock", "UR3+ DR2- y2 ALL5+"),
            ("sq1", "(1,0) / (0,-3)"),
        ] {
            let solution = solve_event(event, algorithm).unwrap();
            assert!(
                EventState::solved(event)
                    .unwrap()
                    .apply(&format!("{algorithm} {solution}"))
                    .unwrap()
                    .is_solved(),
                "{event}: {solution}"
            );
        }
    }
    #[test]
    #[ignore = "cold three-phase tables; run in release verification"]
    fn four_and_fto_solvers() {
        for (event, algorithm) in [("444", "Rw U F2 R'"), ("fto", "R U' BL F")] {
            let solution = solve_event(event, algorithm).unwrap();
            assert!(
                EventState::solved(event)
                    .unwrap()
                    .apply(&format!("{algorithm} {solution}"))
                    .unwrap()
                    .is_solved()
            );
        }
    }
}
