use crate::PuzzleError;
use serde::Serialize;
use serde_json::{Value, json};
use tnoodle_backend::puzzle::*;
use tnoodle_backend::{Puzzle, PuzzleState, Scrambler};

pub const EVENT_IDS: &[&str] = &[
    "222", "333", "444", "555", "666", "777", "333bld", "333fm", "333oh", "444bld", "555bld",
    "333mbld", "clock", "minx", "pyram", "skewb", "sq1", "fto",
];
#[derive(Debug, Clone, Serialize)]
pub struct EventInfo {
    pub id: String,
    pub puzzle: String,
    pub full_solver: bool,
}
pub fn catalog() -> Vec<EventInfo> {
    EVENT_IDS
        .iter()
        .map(|id| EventInfo {
            id: (*id).into(),
            puzzle: base_event(id).unwrap().into(),
            full_solver: matches!(
                base_event(id).unwrap(),
                "222" | "333" | "444" | "pyram" | "skewb" | "sq1" | "fto" | "clock"
            ),
        })
        .collect()
}
pub fn base_event(event: &str) -> Result<&str, PuzzleError> {
    Ok(match event {
        "333bld" | "333fm" | "333oh" | "333mbld" => "333",
        "444bld" => "444",
        "555bld" => "555",
        id if EVENT_IDS.contains(&id) => id,
        _ => {
            return Err(PuzzleError::InvalidState(format!(
                "unsupported event: {event}"
            )));
        }
    })
}
pub fn scrambler(event: &str) -> Result<Scrambler, PuzzleError> {
    Ok(match event {
        "333bld" | "333mbld" => Scrambler::Cube(CubePuzzle::three_by_three_no_inspection()),
        "333fm" => Scrambler::Cube(CubePuzzle::three_by_three_fewest_moves()),
        "444bld" => Scrambler::Cube(CubePuzzle::four_by_four_no_inspection()),
        "555bld" => Scrambler::Cube(CubePuzzle::five_by_five_no_inspection()),
        _ => match base_event(event)? {
            "222" => Scrambler::Cube(CubePuzzle::two_by_two()),
            "333" => Scrambler::Cube(CubePuzzle::three_by_three()),
            "444" => Scrambler::Cube(CubePuzzle::four_by_four()),
            "555" => Scrambler::Cube(CubePuzzle::new(5)),
            "666" => Scrambler::Cube(CubePuzzle::new(6)),
            "777" => Scrambler::Cube(CubePuzzle::new(7)),
            "pyram" => Scrambler::Pyraminx(PyraminxPuzzle::new().with_search_seed(0)),
            "skewb" => Scrambler::Skewb(SkewbPuzzle::new().with_search_seed(0)),
            "clock" => Scrambler::Clock(ClockPuzzle),
            "minx" => Scrambler::Megaminx(MegaminxPuzzle),
            "sq1" => Scrambler::SquareOne(SquareOnePuzzle),
            "fto" => Scrambler::Fto(FtoPuzzle::new()),
            _ => unreachable!(),
        },
    })
}
#[derive(Debug, Clone)]
pub enum EventState {
    Cube(CubeState),
    Clock(ClockState),
    Minx(MegaminxState),
    Pyram(PyraminxState),
    Skewb(SkewbState),
    Sq1(SquareOneState),
    Fto(FtoState),
}
macro_rules! dispatch {
    ($self:expr,$s:ident=>$body:expr) => {
        match $self {
            EventState::Cube($s) => $body,
            EventState::Clock($s) => $body,
            EventState::Minx($s) => $body,
            EventState::Pyram($s) => $body,
            EventState::Skewb($s) => $body,
            EventState::Sq1($s) => $body,
            EventState::Fto($s) => $body,
        }
    };
}
impl EventState {
    pub fn solved(event: &str) -> Result<Self, PuzzleError> {
        Ok(match scrambler(event)? {
            Scrambler::Cube(p) => Self::Cube(p.solved_state()),
            Scrambler::Clock(p) => Self::Clock(p.solved_state()),
            Scrambler::Megaminx(p) => Self::Minx(p.solved_state()),
            Scrambler::Pyraminx(p) => Self::Pyram(p.solved_state()),
            Scrambler::Skewb(p) => Self::Skewb(p.solved_state()),
            Scrambler::SquareOne(p) => Self::Sq1(p.solved_state()),
            Scrambler::Fto(p) => Self::Fto(p.solved_state()),
        })
    }
    pub fn apply(&self, algorithm: &str) -> Result<Self, PuzzleError> {
        let tokens = tokenize(algorithm)?;
        let mut state = self.clone();
        for token in tokens {
            let expanded = if let Self::Cube(cube) = &state {
                expand_cube_token(cube.size(), &token)?
            } else {
                token.clone()
            };
            state = match &state {
                Self::Cube(s) => Self::Cube(s.apply_algorithm(&expanded).map_err(invalid)?),
                Self::Clock(s) => Self::Clock(s.apply_algorithm(&expanded).map_err(invalid)?),
                Self::Minx(s) => Self::Minx(s.apply_algorithm(&expanded).map_err(invalid)?),
                Self::Pyram(s) => Self::Pyram(s.apply_algorithm(&expanded).map_err(invalid)?),
                Self::Skewb(s) => Self::Skewb(s.apply_algorithm(&expanded).map_err(invalid)?),
                Self::Sq1(s) => Self::Sq1(s.apply_algorithm(&expanded).map_err(invalid)?),
                Self::Fto(s) => Self::Fto(s.apply_algorithm(&expanded).map_err(invalid)?),
            };
        }
        Ok(state)
    }
    pub fn is_solved(&self) -> bool {
        dispatch!(self,s=>s.is_solved())
    }
    pub fn normalized_key(&self) -> String {
        dispatch!(self,s=>format!("{:?}",s.normalized()))
    }
    pub fn data(&self) -> Value {
        match self {
            Self::Cube(s) => {
                let n = s.size();
                let faces = [Face::R, Face::U, Face::F, Face::L, Face::D, Face::B];
                json!({"size":n,"image":faces.map(|f|(0..n).map(|r|(0..n).map(|c|"RUFLDB".chars().nth(s.sticker(f,r,c) as usize).unwrap().to_string()).collect::<Vec<_>>()).collect::<Vec<_>>())})
            }
            Self::Pyram(s) => {
                json!({"image":(0..4).map(|f|(0..9).map(|i|s.sticker(f,i)).collect::<Vec<_>>()).collect::<Vec<_>>()})
            }
            Self::Skewb(s) => {
                json!({"image":(0..6).map(|f|(0..5).map(|i|s.sticker(f,i)).collect::<Vec<_>>()).collect::<Vec<_>>()})
            }
            Self::Fto(s) => {
                const MAP: [usize; 72] = [
                    1, 3, 0, 6, 4, 2, 7, 5, 8, 19, 21, 18, 24, 22, 20, 25, 23, 26, 64, 66, 63, 69,
                    67, 65, 70, 68, 71, 46, 48, 45, 51, 49, 47, 52, 50, 53, 55, 57, 54, 60, 58, 56,
                    61, 59, 62, 37, 39, 36, 42, 40, 38, 43, 41, 44, 10, 12, 9, 15, 13, 11, 16, 14,
                    17, 28, 30, 27, 33, 31, 29, 34, 32, 35,
                ];
                const COLORS: [u8; 8] = [0, 6, 1, 7, 5, 3, 4, 2];
                json!({"image":(0..8).map(|f|(0..9).map(|i|{let slot=MAP[f*9+i];COLORS[s.sticker(slot/9,slot%9) as usize]}).collect::<Vec<_>>()).collect::<Vec<_>>()})
            }
            Self::Minx(s) => {
                let faces = [
                    MinxFace::U,
                    MinxFace::BL,
                    MinxFace::BR,
                    MinxFace::R,
                    MinxFace::F,
                    MinxFace::L,
                    MinxFace::D,
                    MinxFace::DR,
                    MinxFace::DBR,
                    MinxFace::B,
                    MinxFace::DBL,
                    MinxFace::DL,
                ];
                json!({"image":faces.map(|f|(0..11).map(|i|s.sticker(f,i)).collect::<Vec<_>>())})
            }
            Self::Clock(s) => {
                json!({"positions":s.positions(),"rightSideUp":s.right_side_up(),"rotations":s.rotations()})
            }
            Self::Sq1(s) => json!({"pieces":s.pieces(),"sliceSolved":s.is_slice_solved()}),
        }
    }
    pub fn svg(&self, event: &str) -> Result<String, PuzzleError> {
        let colors = scrambler(event)?.default_color_scheme();
        Ok(dispatch!(self,s=>s.draw(&colors).to_string()))
    }
}
fn invalid(error: impl std::fmt::Display) -> PuzzleError {
    PuzzleError::InvalidState(error.to_string())
}
pub fn tokenize(algorithm: &str) -> Result<Vec<String>, PuzzleError> {
    // Preserve Square-1 tuples with optional internal whitespace, reject malformed parentheses.
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut tuple = false;
    for ch in algorithm.chars() {
        match ch {
            '(' if !tuple && current.is_empty() => {
                tuple = true;
                current.push(ch)
            }
            ')' if tuple => {
                tuple = false;
                current.push(ch);
                tokens.push(std::mem::take(&mut current));
            }
            '(' | ')' => return Err(invalid("malformed tuple")),
            '/' if !tuple => {
                if !current.is_empty() {
                    tokens.push(std::mem::take(&mut current));
                }
                tokens.push("/".into());
            }
            c if c.is_whitespace() => {
                if !tuple && !current.is_empty() {
                    tokens.push(std::mem::take(&mut current));
                }
            }
            c => current.push(c),
        }
        if tokens.len() > 10000 {
            return Err(PuzzleError::AlgorithmTooLong);
        }
    }
    if tuple {
        return Err(invalid("unclosed tuple"));
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    Ok(tokens)
}
pub fn inverse_event(event: &str, algorithm: &str) -> Result<String, PuzzleError> {
    EventState::solved(event)?.apply(algorithm)?;
    let base = base_event(event)?;
    let mut inverses = Vec::new();
    for token in tokenize(algorithm)?.into_iter().rev() {
        let inv = if token == "/" || (base != "minx" && token.ends_with('2')) || token == "y2" {
            token
        } else if token.starts_with('(') {
            let pair = token
                .trim_matches(['(', ')'])
                .split(',')
                .map(str::parse::<i32>)
                .collect::<Result<Vec<_>, _>>()
                .map_err(invalid)?;
            if pair.len() != 2 {
                return Err(invalid("expected tuple pair"));
            }
            format!("({},{})", -pair[0], -pair[1])
        } else if base == "clock"
            && token.ends_with(['+', '-'])
            && (token.ends_with("0+") || token.ends_with("6+"))
        {
            token
        } else if base == "clock" && token.ends_with(['+', '-']) {
            let end = token.len() - 1;
            format!(
                "{}{}",
                &token[..end],
                if token.ends_with('+') { '-' } else { '+' }
            )
        } else if token.ends_with("++") {
            token.replace("++", "--")
        } else if token.ends_with("--") {
            token.replace("--", "++")
        } else if base == "minx" && token.ends_with('+') {
            token.replace('+', "-")
        } else if base == "minx" && token.ends_with('-') {
            token.replace('-', "+")
        } else if let Some(stem) = token.strip_suffix('\'') {
            stem.into()
        } else {
            format!("{token}'")
        };
        inverses.push(inv);
    }
    Ok(inverses.join(" "))
}

pub fn expand_cube_token(size: usize, token: &str) -> Result<String, PuzzleError> {
    let first = token.chars().next().unwrap_or(' ');
    if "urfdlb".contains(first) {
        return Ok(format!("{}w{}", first.to_ascii_uppercase(), &token[1..]));
    }
    if !matches!(first, 'M' | 'E' | 'S') {
        return Ok(token.into());
    }
    if size.is_multiple_of(2) {
        return Err(invalid("middle slices require an odd cube size"));
    }
    let suffix = &token[1..];
    if !matches!(suffix, "" | "2" | "'") {
        return Err(invalid("invalid middle slice suffix"));
    }
    let face = match first {
        'M' => 'L',
        'E' => 'D',
        _ => 'F',
    };
    let width = size / 2 + 1;
    let turn = |w: usize| {
        if w == 1 {
            face.to_string()
        } else if w == 2 {
            format!("{face}w")
        } else {
            format!("{w}{face}w")
        }
    };
    let opposite = match suffix {
        "" => "'",
        "'" => "",
        _ => "2",
    };
    Ok(format!(
        "{}{suffix} {}{opposite}",
        turn(width),
        turn(width - 1)
    ))
}
#[cfg(test)]
mod migration_tests {
    use super::*;
    #[test]
    fn all_legacy_event_states() {
        let fixtures: Value =
            serde_json::from_str(include_str!("../tests/fixtures/events.json")).unwrap();
        let mut failures = Vec::new();
        for case in fixtures.as_array().unwrap() {
            let event = case["eventId"].as_str().unwrap();
            let algorithm = case["algorithm"].as_str().unwrap();
            match EventState::solved(event).unwrap().apply(algorithm) {
                Ok(state) => {
                    if state.data() != case["state"] {
                        failures.push(format!(
                            "{event} {algorithm}: actual={} expected={}",
                            state.data(),
                            case["state"]
                        ));
                    }
                }
                Err(e) => failures.push(format!("{event} {algorithm}: {e}")),
            }
        }
        assert!(
            failures.is_empty(),
            "{} failures:\n{}",
            failures.len(),
            failures
                .iter()
                .take(8)
                .cloned()
                .collect::<Vec<_>>()
                .join("\n")
        );
    }
}
