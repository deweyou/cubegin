use cubegin_playback::player::{CameraOffset, player_svg_with_camera, player_timeline};

#[test]
fn seeded_square1_scramble_renders_through_every_move() {
    // Standard Square-1 scramble, seed 1552555716.
    let algorithm = "(-5,0) / (0,3) / (2,-1) / (-3,0) / (-2,-5) / (3,0) / (-3,-1) / (3,0) / (3,0) / (6,0) / (-1,-5) / (0,-2) / (1,0)";
    let steps = player_timeline("sq1", algorithm).unwrap().steps.len();
    for step in 0..steps {
        for (progress, camera) in [
            (0.0, CameraOffset::default()),
            (
                0.43,
                CameraOffset {
                    yaw: 1.7,
                    pitch: -0.2,
                },
            ),
            (0.98, CameraOffset::default()),
        ] {
            let svg = player_svg_with_camera("sq1", algorithm, step, progress, camera).unwrap();
            assert!(svg.contains("<polygon"), "step {step} progress {progress}");
        }
    }
}

#[test]
fn wedge_caps_and_side_walls_share_the_cut_outline() {
    let model = player_timeline("sq1", "").unwrap().model;
    for piece in model["pieces"].as_array().unwrap() {
        let id = piece["id"].as_str().unwrap();
        if !id.starts_with("square1-piece-") {
            continue;
        }
        let stickers = piece["stickers"].as_array().unwrap();
        let cut_id = format!("{id}-inner-cut");
        let outline = stickers.iter().find(|s| s["id"] == cut_id).unwrap()["polygon"]
            .as_array()
            .unwrap();
        for sticker in stickers {
            let face = sticker["id"].as_str().unwrap();
            if face.ends_with("-cap-border") || face.contains("-side-border-") {
                for vertex in sticker["polygon"].as_array().unwrap() {
                    assert!(
                        outline
                            .iter()
                            .any(|v| v["x"] == vertex["x"] && v["z"] == vertex["z"]),
                        "{face} protrudes from wedge"
                    );
                }
            }
        }
    }
}
