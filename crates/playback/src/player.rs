//! Platform-neutral piece geometry and rigid transforms. Legacy geometry: 79a1e4c.
use cubegin_puzzle::{
    PuzzleError,
    events::{EventState, base_event, tokenize},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::HashSet, sync::LazyLock};
static DATA: LazyLock<Value> =
    LazyLock::new(|| serde_json::from_str(include_str!("../data/models.json")).unwrap());
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Vector {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}
impl Vector {
    fn norm(self) -> Self {
        let n = (self.x * self.x + self.y * self.y + self.z * self.z).sqrt();
        Self {
            x: self.x / n,
            y: self.y / n,
            z: self.z / n,
        }
    }
    fn add(self, b: Self) -> Self {
        Self {
            x: self.x + b.x,
            y: self.y + b.y,
            z: self.z + b.z,
        }
    }
    fn scale(self, s: f64) -> Self {
        Self {
            x: self.x * s,
            y: self.y * s,
            z: self.z * s,
        }
    }
}
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Quaternion {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub w: f64,
}
impl Quaternion {
    fn axis(axis: Vector, angle: f64) -> Self {
        let a = axis.norm();
        let s = (angle / 2.).sin();
        Self {
            x: a.x * s,
            y: a.y * s,
            z: a.z * s,
            w: (angle / 2.).cos(),
        }
    }
    fn mul(self, b: Self) -> Self {
        let a = self;
        Self {
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        }
    }
    fn rotate(self, v: Vector) -> Vector {
        let q = self
            .mul(Self {
                x: v.x,
                y: v.y,
                z: v.z,
                w: 0.,
            })
            .mul(Self {
                x: -self.x,
                y: -self.y,
                z: -self.z,
                w: self.w,
            });
        Vector {
            x: q.x,
            y: q.y,
            z: q.z,
        }
    }
}
fn invalid(s: impl Into<String>) -> PuzzleError {
    PuzzleError::InvalidState(s.into())
}
fn unique(v: impl Iterator<Item = String>) -> Vec<String> {
    let mut seen = HashSet::new();
    v.filter(|s| seen.insert(s.clone())).collect()
}
fn rotation(ids: Vec<String>, axis: Vector, angle: f64) -> Value {
    json!({"type":"axis-rotation","affectedPieceIds":ids,"axis":axis,"pivot":{"x":0.,"y":0.,"z":0.},"angleRadians":angle})
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerStep {
    pub notation: String,
    pub operations: Vec<Value>,
    pub duration_ms: f64,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerTimeline {
    pub schema_version: u32,
    pub event_id: String,
    pub model: Value,
    pub steps: Vec<PlayerStep>,
    pub total_duration_ms: f64,
}
pub fn player_timeline(event: &str, algorithm: &str) -> Result<PlayerTimeline, PuzzleError> {
    let event_id = base_event(event)?;
    let data = &DATA[event_id];
    if data.is_null() {
        return Err(invalid("no player model"));
    }
    let tokens = tokenize(algorithm)?;
    if tokens.len() > 1000 {
        return Err(PuzzleError::AlgorithmTooLong);
    }
    let ids = data["model"]["pieces"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["id"].as_str().unwrap().to_owned())
        .collect::<Vec<_>>();
    let mut tracking = ids.clone();
    let mut wedges = DATA["sq1"]["initialState"]["wedges"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v["pieceId"].as_str().unwrap().to_owned())
        .collect::<Vec<_>>();
    let mut state = EventState::solved(event)?;
    let mut steps = Vec::new();
    for raw in tokens {
        let token = if raw.chars().next().is_some_and(|c| "urfdlb".contains(c))
            && event_id.as_bytes()[0].is_ascii_digit()
        {
            format!("{}w{}", raw[..1].to_uppercase(), &raw[1..])
        } else {
            raw.clone()
        };
        let after = state.apply(&token)?;
        let mut operations = Vec::new();
        let mut duration = 520.;
        if event_id == "sq1" {
            if token == "/" {
                let affected = unique(
                    wedges[6..12]
                        .iter()
                        .chain(&wedges[12..18])
                        .cloned()
                        .chain(std::iter::once("square1-middle-right".into())),
                );
                operations.push(rotation(
                    affected,
                    Vector {
                        x: 1.,
                        y: 0.,
                        z: 0.27,
                    },
                    -std::f64::consts::PI,
                ));
                let old = wedges.clone();
                wedges[6..12].clone_from_slice(&old[12..18]);
                wedges[12..18].clone_from_slice(&old[6..12]);
                duration *= 1.45;
            } else {
                let numbers = token
                    .trim_matches(['(', ')'])
                    .split(',')
                    .map(|n| {
                        n.trim()
                            .parse::<i32>()
                            .map_err(|_| invalid("invalid tuple"))
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                for (layer, amount) in numbers.into_iter().enumerate() {
                    if amount == 0 {
                        continue;
                    }
                    let range = layer * 12..layer * 12 + 12;
                    operations.push(rotation(
                        unique(wedges[range.clone()].iter().cloned()),
                        Vector {
                            x: 0.,
                            y: 1.,
                            z: 0.,
                        },
                        amount as f64 * std::f64::consts::PI / 6.
                            * if layer == 0 { -1. } else { 1. },
                    ));
                    wedges[range].rotate_right(amount.rem_euclid(12) as usize);
                }
            }
        } else {
            let mut animation = if event_id == "clock" && data["moves"][&token].is_null() {
                let EventState::Clock(clock) = &state else {
                    unreachable!()
                };
                let key = serde_json::to_string(&json!([clock.right_side_up(), clock.rotations()]))
                    .unwrap();
                let split = token
                    .find(|c: char| c.is_ascii_digit())
                    .ok_or_else(|| invalid("invalid clock turn"))?;
                let name = &token[..split];
                let amount = token[split..token.len() - 1]
                    .parse::<f64>()
                    .map_err(|_| invalid("invalid clock amount"))?
                    * if token.ends_with('-') { -1. } else { 1. };
                let mut a = data["frames"][key]["turns"][name].clone();
                if a.is_null() {
                    return Err(invalid("missing clock frame"));
                }
                a["angleRadians"] = json!(a["angleRadians"].as_f64().unwrap() * amount);
                if let Some(angles) = a["angleRadiansByPieceId"].as_object_mut() {
                    for angle in angles.values_mut() {
                        *angle = json!(angle.as_f64().unwrap() * amount);
                    }
                }
                a["durationMultiplier"] = json!(if amount == 0. {
                    0.7
                } else {
                    2. * (amount.abs() / 3.).clamp(0.65, 1.65)
                });
                a
            } else {
                data["moves"][&token]["animation"].clone()
            };
            if animation.is_null() {
                return Err(invalid(format!("unsupported player move: {event}/{token}")));
            }
            if event_id != "clock" {
                let remap = |s: &str| tracking[ids.iter().position(|id| id == s).unwrap()].clone();
                for key in ["affectedPieceIds", "rotationAffectedPieceIds"] {
                    if let Some(values) = animation[key].as_array_mut() {
                        for id in values {
                            *id = json!(remap(id.as_str().unwrap()));
                        }
                    }
                }
                let permutation = data["moves"][&token]["sourceByTarget"].as_array().unwrap();
                tracking = permutation
                    .iter()
                    .map(|i| tracking[i.as_u64().unwrap() as usize].clone())
                    .collect();
            }
            duration *= animation["durationMultiplier"].as_f64().unwrap_or(1.);
            animation["type"] = json!("axis-rotation");
            operations.push(animation);
        }
        steps.push(PlayerStep {
            notation: raw,
            operations,
            duration_ms: duration,
        });
        state = after;
    }
    let total_duration_ms = steps.iter().map(|s| s.duration_ms).sum();
    Ok(PlayerTimeline {
        schema_version: 1,
        event_id: event.into(),
        model: data["model"].clone(),
        steps,
        total_duration_ms,
    })
}
/// Deterministic arbitrary seek. `completed` is the number of completed moves, then
/// `progress` interpolates the following move (0..1). No UI clock is consulted.
pub fn player_frame(
    event: &str,
    algorithm: &str,
    completed: usize,
    progress: f64,
) -> Result<Value, PuzzleError> {
    let timeline = player_timeline(event, algorithm)?;
    if completed > timeline.steps.len() || !progress.is_finite() || !(0.0..=1.).contains(&progress)
    {
        return Err(invalid("invalid animation position"));
    }
    let mut model = timeline.model;
    for (index, step) in timeline
        .steps
        .iter()
        .enumerate()
        .take((completed + 1).min(timeline.steps.len()))
    {
        let t = if index < completed { 1. } else { progress };
        for operation in &step.operations {
            apply_operation(&mut model, operation, t);
        }
    }
    Ok(model)
}
fn apply_operation(model: &mut Value, op: &Value, t: f64) {
    let axis: Vector = serde_json::from_value(op["axis"].clone()).unwrap();
    let pivot: Vector = serde_json::from_value(op["pivot"].clone()).unwrap();
    for p in model["pieces"].as_array_mut().unwrap() {
        let id = p["id"].as_str().unwrap().to_owned();
        if !op["affectedPieceIds"]
            .as_array()
            .unwrap()
            .iter()
            .any(|v| v.as_str() == Some(&id))
        {
            continue;
        }
        let angle = op["angleRadiansByPieceId"][&id]
            .as_f64()
            .unwrap_or_else(|| op["angleRadians"].as_f64().unwrap())
            * t;
        let q = Quaternion::axis(axis, angle);
        let old: Quaternion = serde_json::from_value(p["orientation"].clone()).unwrap();
        p["orientation"] = serde_json::to_value(q.mul(old)).unwrap();
        let mut position: Vector = serde_json::from_value(p["position"].clone()).unwrap();
        if op["rotateInPlace"] != true {
            position = q.rotate(position.add(pivot.scale(-1.))).add(pivot);
        }
        if t > 0. && t < 1. {
            if let Ok(pulse) =
                serde_json::from_value::<Vector>(op["positionPulseByPieceId"][&id].clone())
            {
                position = position.add(pulse.scale((std::f64::consts::PI * t).sin()));
            }
            for sticker in p["stickers"].as_array_mut().unwrap() {
                let color = &op["colorPulseByStickerId"][sticker["id"].as_str().unwrap()];
                if color.is_string() {
                    sticker["color"] = color.clone();
                }
            }
        }
        p["position"] = serde_json::to_value(position).unwrap();
    }
}
/// Orthographic, depth-sorted SVG of the same 3D frame, usable on all platforms.
pub fn player_svg(
    event: &str,
    algorithm: &str,
    completed: usize,
    progress: f64,
) -> Result<String, PuzzleError> {
    let model = player_frame(event, algorithm, completed, progress)?;
    let scale = 400. / model["cameraDistance"].as_f64().unwrap();
    let yaw = model["cameraOrbit"]["yaw"].as_f64().unwrap_or(0.6);
    let pitch = model["cameraOrbit"]["pitch"].as_f64().unwrap_or(0.5);
    let camera = Quaternion::axis(
        Vector {
            x: 1.,
            y: 0.,
            z: 0.,
        },
        pitch,
    )
    .mul(Quaternion::axis(
        Vector {
            x: 0.,
            y: 1.,
            z: 0.,
        },
        -yaw,
    ));
    let mut polygons = Vec::new();
    for p in model["pieces"].as_array().unwrap() {
        let pos: Vector = serde_json::from_value(p["position"].clone()).unwrap();
        let q: Quaternion = serde_json::from_value(p["orientation"].clone()).unwrap();
        let mut surfaces: Vec<(Vec<Vector>, String, bool)> = p["stickers"]
            .as_array()
            .unwrap()
            .iter()
            .map(|sticker| {
                (
                    sticker["polygon"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|v| serde_json::from_value(v.clone()).unwrap())
                        .collect(),
                    sticker["color"].as_str().unwrap().to_owned(),
                    sticker["renderSide"] == "front",
                )
            })
            .collect();
        if p["body"]["type"] == "box" {
            let h = p["body"]["size"].as_f64().unwrap() / 2.;
            let corners = (0..8)
                .map(|i| Vector {
                    x: if i & 1 == 0 { -h } else { h },
                    y: if i & 2 == 0 { -h } else { h },
                    z: if i & 4 == 0 { -h } else { h },
                })
                .collect::<Vec<_>>();
            for face in [
                [0, 1, 3, 2],
                [4, 6, 7, 5],
                [0, 4, 5, 1],
                [2, 3, 7, 6],
                [0, 2, 6, 4],
                [1, 5, 7, 3],
            ] {
                surfaces.push((
                    face.map(|i| corners[i]).to_vec(),
                    p["body"]["color"].as_str().unwrap().into(),
                    false,
                ));
            }
        }
        for (surface, color, front_only) in surfaces {
            let vertices = surface
                .into_iter()
                .map(|v| camera.rotate(q.rotate(v).add(pos)))
                .collect::<Vec<_>>();
            if vertices.len() < 3 {
                continue;
            }
            let a = vertices[1].add(vertices[0].scale(-1.));
            let b = vertices[2].add(vertices[0].scale(-1.));
            if a.x * b.y - a.y * b.x <= 0. && front_only {
                continue;
            }
            let depth = vertices.iter().map(|v| v.z).sum::<f64>() / vertices.len() as f64;
            let points = vertices
                .iter()
                .map(|v| format!("{:.3},{:.3}", 150. + v.x * scale, 150. - v.y * scale))
                .collect::<Vec<_>>()
                .join(" ");
            polygons.push((depth,format!("<polygon points=\"{points}\" fill=\"{}\" stroke=\"#111827\" stroke-width=\"0.35\"/>",color)));
        }
    }
    polygons.sort_by(|a, b| a.0.total_cmp(&b.0));
    Ok(format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 300 300\" role=\"img\" aria-label=\"Puzzle animation frame\">{}</svg>",
        polygons.into_iter().map(|(_, p)| p).collect::<String>()
    ))
}
