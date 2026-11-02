pub mod events;
use serde::Serialize;
use std::fmt;
use thiserror::Error;

pub const SOLVED: &str = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB";
pub const FACES: &[u8; 6] = b"URFDLB";
pub const CORNERS: [[usize; 3]; 8] = [
    [8, 9, 20],
    [6, 18, 38],
    [0, 36, 47],
    [2, 45, 11],
    [29, 26, 15],
    [27, 44, 24],
    [33, 53, 42],
    [35, 17, 51],
];
pub const EDGES: [[usize; 2]; 12] = [
    [5, 10],
    [7, 19],
    [3, 37],
    [1, 46],
    [32, 16],
    [28, 25],
    [30, 43],
    [34, 52],
    [23, 12],
    [21, 41],
    [50, 39],
    [48, 14],
];

#[derive(Debug, Error, PartialEq, Eq)]
pub enum PuzzleError {
    #[error("invalid move at token {index}: {token}")]
    InvalidMove { index: usize, token: String },
    #[error("invalid cube state: {0}")]
    InvalidState(String),
    #[error("algorithm exceeds 10000 moves")]
    AlgorithmTooLong,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Move {
    face: u8,
    turns: u8,
}
impl Move {
    pub fn face(self) -> char {
        FACES[self.face as usize] as char
    }
    pub fn turns(self) -> u8 {
        self.turns
    }
    pub fn inverse(self) -> Self {
        Self {
            turns: 4 - self.turns,
            ..self
        }
    }
}
impl fmt::Display for Move {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}{}",
            self.face(),
            match self.turns {
                2 => "2",
                3 => "'",
                _ => "",
            }
        )
    }
}
// Move fields are private; deserialize through the parser rather than trusting foreign values.
pub fn parse(algorithm: &str) -> Result<Vec<Move>, PuzzleError> {
    algorithm
        .split_whitespace()
        .enumerate()
        .map(|(index, token)| {
            if index >= 10000 {
                return Err(PuzzleError::AlgorithmTooLong);
            }
            let invalid = || PuzzleError::InvalidMove {
                index,
                token: token.into(),
            };
            let bytes = token.as_bytes();
            let face = bytes
                .first()
                .and_then(|c| FACES.iter().position(|f| f == c))
                .ok_or_else(invalid)?;
            let turns = match &bytes[1..] {
                [] => 1,
                b"2" => 2,
                b"'" => 3,
                _ => return Err(invalid()),
            };
            Ok(Move {
                face: face as u8,
                turns,
            })
        })
        .collect()
}
pub fn format(moves: &[Move]) -> String {
    moves
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(" ")
}
pub fn inverse(algorithm: &str) -> Result<String, PuzzleError> {
    Ok(format(
        &parse(algorithm)?
            .into_iter()
            .rev()
            .map(Move::inverse)
            .collect::<Vec<_>>(),
    ))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cube([u8; 54]);
impl Default for Cube {
    fn default() -> Self {
        Self(SOLVED.as_bytes().try_into().unwrap())
    }
}
impl Cube {
    pub fn from_facelets(facelets: &str) -> Result<Self, PuzzleError> {
        let fail = |reason: &str| PuzzleError::InvalidState(reason.into());
        let bytes: [u8; 54] = facelets
            .as_bytes()
            .try_into()
            .map_err(|_| fail("expected 54 ASCII facelets in URFDLB order"))?;
        for (face, color) in FACES.iter().enumerate() {
            if bytes[face * 9 + 4] != *color || bytes.iter().filter(|c| *c == color).count() != 9 {
                return Err(fail(
                    "expected fixed centers and nine stickers of each color",
                ));
            }
        }
        let mut cp = Vec::new();
        let mut co = 0;
        for indices in CORNERS {
            let colors = indices.map(|i| bytes[i]);
            let ori = colors
                .iter()
                .position(|c| *c == b'U' || *c == b'D')
                .ok_or_else(|| fail("invalid corner"))?;
            let id = CORNERS
                .iter()
                .position(|home| (0..3).all(|i| bytes_of_solved(home[i]) == colors[(i + ori) % 3]))
                .ok_or_else(|| fail("invalid corner colors"))?;
            cp.push(id);
            co += ori;
        }
        let mut ep = Vec::new();
        let mut eo = 0;
        for indices in EDGES {
            let colors = indices.map(|i| bytes[i]);
            let (id, ori) = EDGES
                .iter()
                .enumerate()
                .find_map(|(id, home)| {
                    (0..2)
                        .find(|ori| {
                            (0..2).all(|i| bytes_of_solved(home[i]) == colors[(i + ori) % 2])
                        })
                        .map(|ori| (id, ori))
                })
                .ok_or_else(|| fail("invalid edge colors"))?;
            ep.push(id);
            eo += ori;
        }
        let unique = |p: &[usize]| (0..p.len()).all(|i| p.iter().filter(|j| **j == i).count() == 1);
        if !unique(&cp) || !unique(&ep) {
            return Err(fail("duplicate cubies"));
        }
        if co % 3 != 0 || eo % 2 != 0 || parity(&cp) != parity(&ep) {
            return Err(fail("corner twist, edge flip, or permutation parity"));
        }
        Ok(Self(bytes))
    }
    pub fn facelets(&self) -> String {
        String::from_utf8(self.0.to_vec()).unwrap()
    }
    pub fn is_solved(&self) -> bool {
        self == &Self::default()
    }
    pub fn apply(&self, algorithm: &str) -> Result<Self, PuzzleError> {
        let mut cube = self.clone();
        for turn in parse(algorithm)? {
            cube.apply_move(turn);
        }
        Ok(cube)
    }
    pub fn apply_move(&mut self, turn: Move) {
        let axis = NORMALS[turn.face as usize];
        for _ in 0..turn.turns {
            let before = self.0;
            for (index, color) in before.into_iter().enumerate() {
                let (position, normal) = sticker_geometry(index);
                if dot(position, axis) == 1 {
                    let position = rotate_clockwise(position, axis);
                    let normal = rotate_clockwise(normal, axis);
                    let target = (0..54)
                        .find(|i| sticker_geometry(*i) == (position, normal))
                        .unwrap();
                    self.0[target] = color;
                }
            }
        }
    }
}
fn bytes_of_solved(i: usize) -> u8 {
    SOLVED.as_bytes()[i]
}
pub fn parity(p: &[usize]) -> usize {
    (0..p.len())
        .map(|i| (i + 1..p.len()).filter(|j| p[i] > p[*j]).count())
        .sum::<usize>()
        % 2
}

pub const NORMALS: [[i8; 3]; 6] = [
    [0, 1, 0],
    [1, 0, 0],
    [0, 0, 1],
    [0, -1, 0],
    [-1, 0, 0],
    [0, 0, -1],
];
const RIGHTS: [[i8; 3]; 6] = [
    [1, 0, 0],
    [0, 0, -1],
    [1, 0, 0],
    [1, 0, 0],
    [0, 0, 1],
    [-1, 0, 0],
];
const DOWNS: [[i8; 3]; 6] = [
    [0, 0, 1],
    [0, -1, 0],
    [0, -1, 0],
    [0, 0, -1],
    [0, -1, 0],
    [0, -1, 0],
];
pub fn sticker_geometry(index: usize) -> ([i8; 3], [i8; 3]) {
    let face = index / 9;
    let row = (index % 9 / 3) as i8 - 1;
    let col = (index % 3) as i8 - 1;
    (
        std::array::from_fn(|i| NORMALS[face][i] + RIGHTS[face][i] * col + DOWNS[face][i] * row),
        NORMALS[face],
    )
}
fn dot(a: [i8; 3], b: [i8; 3]) -> i8 {
    a.into_iter().zip(b).map(|(a, b)| a * b).sum()
}
fn rotate_clockwise(v: [i8; 3], n: [i8; 3]) -> [i8; 3] {
    let cross = [
        n[1] * v[2] - n[2] * v[1],
        n[2] * v[0] - n[0] * v[2],
        n[0] * v[1] - n[1] * v[0],
    ];
    std::array::from_fn(|i| n[i] * dot(n, v) - cross[i])
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    #[test]
    fn legacy_states() {
        let cases: serde_json::Value =
            serde_json::from_str(include_str!("../tests/fixtures/states.json")).unwrap();
        for case in cases.as_array().unwrap() {
            let alg = case["algorithm"].as_str().unwrap();
            let cube = Cube::default().apply(alg).unwrap();
            assert_eq!(cube.facelets(), case["facelets"].as_str().unwrap(), "{alg}");
            assert_eq!(Cube::from_facelets(&cube.facelets()).unwrap(), cube);
        }
    }
    #[test]
    fn rejects_invalid_notation() {
        for s in ["r", "Rw", "R3", "R2'", "x", "R;", "2", "💥"] {
            assert!(parse(s).is_err(), "{s}");
        }
    }
    #[test]
    fn rejects_impossible_states() {
        for changes in [vec![(5, 10)], vec![(8, 9), (9, 20)], vec![(5, 7), (10, 19)]] {
            let mut s = SOLVED.as_bytes().to_vec();
            for (a, b) in changes {
                s.swap(a, b);
            }
            assert!(Cube::from_facelets(std::str::from_utf8(&s).unwrap()).is_err());
        }
        for s in ["", &"U".repeat(54), &"💥".repeat(54)] {
            assert!(Cube::from_facelets(s).is_err());
        }
    }
    proptest! {
        #[test] fn inverse_and_legal_state(turns in prop::collection::vec(0usize..18, 0..80)) {
            let moves = turns.into_iter().map(|i| Move{ face:(i/3) as u8,turns:(i%3+1) as u8 }).collect::<Vec<_>>();
            let alg = format(&moves); let cube = Cube::default().apply(&alg).unwrap();
            prop_assert_eq!(Cube::from_facelets(&cube.facelets()).unwrap(),cube.clone());
            prop_assert!(cube.apply(&inverse(&alg).unwrap()).unwrap().is_solved());
        }
    }
}
