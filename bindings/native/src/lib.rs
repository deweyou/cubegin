uniffi::setup_scaffolding!();
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CubeginError {
    #[error("invalid input: {reason}")]
    InvalidInput { reason: String },
    #[error("computation failed: {reason}")]
    Computation { reason: String },
}
impl From<cubegin::PuzzleError> for CubeginError {
    fn from(error: cubegin::PuzzleError) -> Self {
        Self::InvalidInput {
            reason: error.to_string(),
        }
    }
}
impl From<cubegin::SolveError> for CubeginError {
    fn from(error: cubegin::SolveError) -> Self {
        match error {
            cubegin::SolveError::InvalidInput(e) => e.into(),
            other => Self::Computation {
                reason: other.to_string(),
            },
        }
    }
}
#[derive(uniffi::Record)]
pub struct Snapshot {
    pub facelets: String,
    pub solved: bool,
    pub svg: String,
}
#[derive(uniffi::Record)]
pub struct Scramble {
    pub algorithm: String,
    pub facelets: String,
    pub seed: u32,
}
#[derive(uniffi::Record)]
pub struct Step {
    pub notation: String,
    pub axis: Vec<i8>,
    pub angle_radians: f64,
    pub duration_ms: u32,
    pub before: String,
    pub after: String,
}
#[uniffi::export]
pub fn version() -> String {
    cubegin::VERSION.into()
}
#[uniffi::export]
pub fn evaluate(algorithm: String) -> Result<Snapshot, CubeginError> {
    let s = cubegin::evaluate(&algorithm)?;
    Ok(Snapshot {
        facelets: s.facelets,
        solved: s.solved,
        svg: s.svg,
    })
}
#[uniffi::export]
pub fn inverse(algorithm: String) -> Result<String, CubeginError> {
    Ok(cubegin::inverse(&algorithm)?)
}
#[uniffi::export]
pub fn solve(facelets: String) -> Result<String, CubeginError> {
    Ok(cubegin::solve(&facelets)?)
}
#[uniffi::export]
pub fn scramble(seed: u32) -> Result<Scramble, CubeginError> {
    let s = cubegin::scramble(seed)?;
    Ok(Scramble {
        algorithm: s.algorithm,
        facelets: s.facelets,
        seed: s.seed,
    })
}
#[uniffi::export]
pub fn render(facelets: String) -> Result<String, CubeginError> {
    Ok(cubegin::render(&facelets)?)
}
#[uniffi::export]
pub fn timeline(algorithm: String) -> Result<Vec<Step>, CubeginError> {
    Ok(cubegin::timeline(&cubegin::Cube::default(), &algorithm)?
        .into_iter()
        .map(|s| Step {
            notation: s.notation,
            axis: s.axis.to_vec(),
            angle_radians: s.angle_radians,
            duration_ms: s.duration_ms,
            before: s.before,
            after: s.after,
        })
        .collect())
}

// Event state is a versioned JSON record because puzzles have different topology.
#[derive(uniffi::Record)]
pub struct EventSnapshot {
    pub event_id: String,
    pub state_json: String,
    pub solved: bool,
    pub svg: String,
}
#[derive(uniffi::Record)]
pub struct EventScramble {
    pub event_id: String,
    pub algorithm: String,
    pub seed: u32,
    pub state_json: String,
}
#[uniffi::export]
pub fn event_catalog() -> String {
    serde_json::to_string(&cubegin::events::catalog()).unwrap()
}
#[uniffi::export]
pub fn evaluate_event(event: String, algorithm: String) -> Result<EventSnapshot, CubeginError> {
    let s = cubegin::events::evaluate_event(&event, &algorithm)?;
    Ok(EventSnapshot {
        event_id: s.event_id,
        state_json: s.state.to_string(),
        solved: s.solved,
        svg: s.svg,
    })
}
fn event_scramble_record(s: cubegin::events::EventScramble) -> EventScramble {
    EventScramble {
        event_id: s.event_id,
        algorithm: s.algorithm,
        seed: s.seed,
        state_json: s.state.to_string(),
    }
}
#[uniffi::export]
pub fn generate_event(event: String, seed: u32) -> Result<EventScramble, CubeginError> {
    Ok(event_scramble_record(cubegin::events::generate_event(
        &event, seed,
    )?))
}
#[uniffi::export]
pub fn generate_multi_blind(seed: u32, count: u32) -> Result<Vec<EventScramble>, CubeginError> {
    Ok(cubegin::events::generate_multi_blind(seed, count)?
        .into_iter()
        .map(event_scramble_record)
        .collect())
}
#[uniffi::export]
pub fn inverse_event(event: String, algorithm: String) -> Result<String, CubeginError> {
    Ok(cubegin::events::inverse_event(&event, &algorithm)?)
}
#[uniffi::export]
pub fn solve_event(event: String, algorithm: String) -> Result<String, CubeginError> {
    Ok(cubegin::events::solve_event(&event, &algorithm)?)
}
#[uniffi::export]
pub fn timeline_event(event: String, algorithm: String) -> Result<String, CubeginError> {
    Ok(serde_json::to_string(&cubegin::events::timeline_event(&event, &algorithm)?).unwrap())
}

#[uniffi::export]
pub fn type_catalog() -> String {
    serde_json::to_string(&cubegin::events::type_catalog()).unwrap()
}

#[uniffi::export]
pub fn training_cases(id: String) -> String {
    serde_json::to_string(&cubegin::events::cases(&id)).unwrap()
}

#[uniffi::export]
pub fn assist_methods() -> String {
    serde_json::to_string(&cubegin::events::METHODS).unwrap()
}

#[uniffi::export]
pub fn generate_training(
    id: String,
    seed: u32,
    options_json: String,
) -> Result<String, CubeginError> {
    let options: cubegin::events::TrainingOptions =
        serde_json::from_str(&options_json).map_err(|e| CubeginError::InvalidInput {
            reason: e.to_string(),
        })?;
    Ok(serde_json::to_string(&cubegin::events::generate_training(&id, seed, &options)?).unwrap())
}

#[uniffi::export]
pub fn solve_assist(
    event: String,
    methods_json: String,
    algorithm: String,
    options_json: String,
) -> Result<String, CubeginError> {
    let options: cubegin::events::AssistOptions =
        serde_json::from_str(&options_json).map_err(|e| CubeginError::InvalidInput {
            reason: e.to_string(),
        })?;
    let methods: Vec<String> =
        serde_json::from_str(&methods_json).map_err(|e| CubeginError::InvalidInput {
            reason: e.to_string(),
        })?;
    Ok(serde_json::to_string(&cubegin::events::solve_assist(
        &event, &methods, &algorithm, &options,
    )?)
    .unwrap())
}

#[uniffi::export]
pub fn player_timeline(event: String, algorithm: String) -> Result<String, CubeginError> {
    Ok(serde_json::to_string(&cubegin::events::player_timeline(&event, &algorithm)?).unwrap())
}

#[uniffi::export]
pub fn player_frame(
    event: String,
    algorithm: String,
    completed: u32,
    progress: f64,
) -> Result<String, CubeginError> {
    Ok(serde_json::to_string(&cubegin::events::player_frame(
        &event,
        &algorithm,
        completed as usize,
        progress,
    )?)
    .unwrap())
}

#[uniffi::export]
pub fn player_svg(
    event: String,
    algorithm: String,
    completed: u32,
    progress: f64,
) -> Result<String, CubeginError> {
    Ok(cubegin::events::player_svg(
        &event,
        &algorithm,
        completed as usize,
        progress,
    )?)
}
#[uniffi::export]
pub fn validate_fmc(scramble: String, solution: String) -> String {
    serde_json::to_string(&cubegin::events::validate_fmc(&scramble, &solution)).unwrap()
}

#[uniffi::export]
pub fn generate_batch(
    id: String,
    seed: u32,
    count: u32,
    options_json: String,
) -> Result<String, CubeginError> {
    let options: cubegin::events::TrainingOptions =
        serde_json::from_str(&options_json).map_err(|e| CubeginError::InvalidInput {
            reason: e.to_string(),
        })?;
    Ok(serde_json::to_string(&cubegin::events::generate_batch(
        &id, seed, count, &options,
    )?)
    .unwrap())
}
