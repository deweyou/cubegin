use wasm_bindgen::prelude::*;
fn error(error: impl std::fmt::Display) -> JsValue {
    js_sys_error(&error.to_string())
}
fn js_sys_error(message: &str) -> JsValue {
    JsValue::from_str(message)
}
#[wasm_bindgen]
pub fn version() -> String {
    cubegin::VERSION.into()
}
#[wasm_bindgen]
pub fn evaluate(algorithm: &str) -> Result<String, JsValue> {
    serde_json::to_string(&cubegin::evaluate(algorithm).map_err(error)?).map_err(error)
}
#[wasm_bindgen]
pub fn inverse(algorithm: &str) -> Result<String, JsValue> {
    cubegin::inverse(algorithm).map_err(error)
}
#[wasm_bindgen]
pub fn solve(facelets: &str) -> Result<String, JsValue> {
    cubegin::solve(facelets).map_err(error)
}
#[wasm_bindgen]
pub fn scramble(seed: u32) -> Result<String, JsValue> {
    serde_json::to_string(&cubegin::scramble(seed).map_err(error)?).map_err(error)
}
#[wasm_bindgen]
pub fn render(facelets: &str) -> Result<String, JsValue> {
    cubegin::render(facelets).map_err(error)
}
#[wasm_bindgen]
pub fn timeline(algorithm: &str) -> Result<String, JsValue> {
    serde_json::to_string(&cubegin::timeline(&cubegin::Cube::default(), algorithm).map_err(error)?)
        .map_err(error)
}

#[wasm_bindgen]
pub fn event_catalog() -> Result<String, JsValue> {
    serde_json::to_string(&cubegin::events::catalog()).map_err(error)
}
#[wasm_bindgen]
pub fn evaluate_event(event: &str, algorithm: &str) -> Result<String, JsValue> {
    serde_json::to_string(&cubegin::events::evaluate_event(event, algorithm).map_err(error)?)
        .map_err(error)
}
#[wasm_bindgen]
pub fn generate_event(event: &str, seed: u32) -> Result<String, JsValue> {
    serde_json::to_string(&cubegin::events::generate_event(event, seed).map_err(error)?)
        .map_err(error)
}
#[wasm_bindgen]
pub fn generate_multi_blind(seed: u32, count: u32) -> Result<String, JsValue> {
    serde_json::to_string(&cubegin::events::generate_multi_blind(seed, count).map_err(error)?)
        .map_err(error)
}
#[wasm_bindgen]
pub fn inverse_event(event: &str, algorithm: &str) -> Result<String, JsValue> {
    cubegin::events::inverse_event(event, algorithm).map_err(error)
}
#[wasm_bindgen]
pub fn solve_event(event: &str, algorithm: &str) -> Result<String, JsValue> {
    cubegin::events::solve_event(event, algorithm).map_err(error)
}
#[wasm_bindgen]
pub fn timeline_event(event: &str, algorithm: &str) -> Result<String, JsValue> {
    serde_json::to_string(&cubegin::events::timeline_event(event, algorithm).map_err(error)?)
        .map_err(error)
}

#[wasm_bindgen]
pub fn type_catalog() -> String {
    serde_json::to_string(&cubegin::events::type_catalog()).unwrap()
}

#[wasm_bindgen]
pub fn training_cases(id: String) -> String {
    serde_json::to_string(&cubegin::events::cases(&id)).unwrap()
}

#[wasm_bindgen]
pub fn assist_methods() -> String {
    serde_json::to_string(&cubegin::events::METHODS).unwrap()
}

#[wasm_bindgen]
pub fn generate_training(id: String, seed: u32, options_json: String) -> Result<String, JsValue> {
    let options: cubegin::events::TrainingOptions =
        serde_json::from_str(&options_json).map_err(error)?;
    Ok(serde_json::to_string(
        &cubegin::events::generate_training(&id, seed, &options).map_err(error)?,
    )
    .unwrap())
}

#[wasm_bindgen]
pub fn solve_assist(
    event: String,
    methods_json: String,
    algorithm: String,
    options_json: String,
) -> Result<String, JsValue> {
    let options: cubegin::events::AssistOptions =
        serde_json::from_str(&options_json).map_err(error)?;
    let methods: Vec<String> = serde_json::from_str(&methods_json).map_err(error)?;
    Ok(serde_json::to_string(
        &cubegin::events::solve_assist(&event, &methods, &algorithm, &options).map_err(error)?,
    )
    .unwrap())
}

#[wasm_bindgen]
pub fn player_timeline(event: String, algorithm: String) -> Result<String, JsValue> {
    Ok(
        serde_json::to_string(
            &cubegin::events::player_timeline(&event, &algorithm).map_err(error)?,
        )
        .unwrap(),
    )
}

#[wasm_bindgen]
pub fn player_frame(
    event: String,
    algorithm: String,
    completed: u32,
    progress: f64,
) -> Result<String, JsValue> {
    Ok(serde_json::to_string(
        &cubegin::events::player_frame(&event, &algorithm, completed as usize, progress)
            .map_err(error)?,
    )
    .unwrap())
}

#[wasm_bindgen]
pub fn player_svg(
    event: String,
    algorithm: String,
    completed: u32,
    progress: f64,
) -> Result<String, JsValue> {
    cubegin::events::player_svg(&event, &algorithm, completed as usize, progress).map_err(error)
}
#[wasm_bindgen]
pub fn validate_fmc(scramble: String, solution: String) -> String {
    serde_json::to_string(&cubegin::events::validate_fmc(&scramble, &solution)).unwrap()
}

#[wasm_bindgen]
pub fn generate_batch(
    id: String,
    seed: u32,
    count: u32,
    options_json: String,
) -> Result<String, JsValue> {
    let options: cubegin::events::TrainingOptions =
        serde_json::from_str(&options_json).map_err(error)?;
    Ok(serde_json::to_string(
        &cubegin::events::generate_batch(&id, seed, count, &options).map_err(error)?,
    )
    .unwrap())
}
