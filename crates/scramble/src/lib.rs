pub mod events;
mod subgroup;
pub mod training;
use cubegin_puzzle::{CORNERS, Cube, EDGES, SOLVED, inverse, parity};
use cubegin_solver::{SolveError, solve};
use rand::{Rng, SeedableRng, seq::SliceRandom};
use rand_chacha::ChaCha8Rng;

/// Reproducible random-state scramble. Seeded diagnostic API, not WCA competition certification.
/// Permutations are shuffled, parity matched, and final orientations constrained to legal sums.
pub fn generate(seed: u32) -> Result<(String, String), SolveError> {
    let mut rng = ChaCha8Rng::seed_from_u64(seed.into());
    let mut cp: Vec<_> = (0..8).collect();
    let mut ep: Vec<_> = (0..12).collect();
    cp.shuffle(&mut rng);
    ep.shuffle(&mut rng);
    if parity(&cp) != parity(&ep) {
        ep.swap(0, 1);
    }
    let mut facelets = SOLVED.as_bytes().to_vec();
    let mut twist = 0;
    for i in 0..8 {
        let orientation = if i == 7 {
            (3 - twist % 3) % 3
        } else {
            rng.gen_range(0..3)
        };
        twist += orientation;
        for j in 0..3 {
            facelets[CORNERS[i][(j + orientation) % 3]] = SOLVED.as_bytes()[CORNERS[cp[i]][j]];
        }
    }
    let mut flip = 0;
    for i in 0..12 {
        let orientation = if i == 11 {
            flip % 2
        } else {
            rng.gen_range(0..2)
        };
        flip += orientation;
        for j in 0..2 {
            facelets[EDGES[i][(j + orientation) % 2]] = SOLVED.as_bytes()[EDGES[ep[i]][j]];
        }
    }
    let facelets = String::from_utf8(facelets).unwrap();
    let algorithm = inverse(&solve(&facelets)?)?;
    if Cube::default().apply(&algorithm)?.facelets() != facelets {
        return Err(SolveError::InvalidSolution);
    }
    Ok((algorithm, facelets))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn random_states_replay_and_solve() {
        for seed in 0..12 {
            let (algorithm, state) = generate(seed).unwrap();
            assert_eq!(Cube::default().apply(&algorithm).unwrap().facelets(), state);
            assert!(
                Cube::from_facelets(&state)
                    .unwrap()
                    .apply(&solve(&state).unwrap())
                    .unwrap()
                    .is_solved()
            );
            assert_eq!(generate(seed).unwrap(), (algorithm, state));
        }
    }
}
