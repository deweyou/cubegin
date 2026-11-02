use cubegin_playback::player::*;
#[test]
fn all_models_move_and_inverse() {
    for (event, algorithm) in [
        ("222", "R U F"),
        ("333", "M E S Rw x y2 z'"),
        ("444", "Rw U 3Fw"),
        ("555", "3Rw U M"),
        ("666", "3Rw U 4Fw"),
        ("777", "M 3Rw U"),
        ("pyram", "R U l b'"),
        ("skewb", "R U B"),
        ("fto", "U R BL BR"),
        ("minx", "R++ D-- U R F2'"),
        ("sq1", "(1,0) / (0,3) /"),
        ("clock", "UR3+ y2 U2- z R1+ x2 ALL5+"),
    ] {
        let inverse = cubegin_puzzle::events::inverse_event(event, algorithm).unwrap();
        let full = format!("{algorithm} {inverse}");
        let timeline = player_timeline(event, &full).unwrap();
        let frame = player_frame(event, &full, timeline.steps.len(), 0.).unwrap();
        for (a, b) in timeline.model["pieces"]
            .as_array()
            .unwrap()
            .iter()
            .zip(frame["pieces"].as_array().unwrap())
        {
            for axis in ["x", "y", "z"] {
                let delta =
                    a["position"][axis].as_f64().unwrap() - b["position"][axis].as_f64().unwrap();
                assert!(delta.abs() < 1e-8, "{event} {} {axis} {delta}", a["id"]);
            }
            let dot = ["x", "y", "z", "w"]
                .iter()
                .map(|k| {
                    a["orientation"][k].as_f64().unwrap() * b["orientation"][k].as_f64().unwrap()
                })
                .sum::<f64>()
                .abs();
            assert!((dot - 1.).abs() < 1e-8, "{event} {} {dot}", a["id"]);
        }
        assert!(
            player_svg(event, algorithm, 0, 0.5)
                .unwrap()
                .contains("<polygon")
        );
    }
}
#[test]
fn reject_invalid_seek_and_moves() {
    assert!(player_frame("333", "R", 2, 0.).is_err());
    assert!(player_frame("333", "R", 0, f64::NAN).is_err());
    assert!(player_timeline("sq1", "(2,0) /").is_err());
}
