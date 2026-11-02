use cubegin_scramble::training::*;
use serde_json::Value;
#[test]
fn oracle_certified_training_states() {
    let fixtures: Vec<Value> =
        serde_json::from_str(include_str!("fixtures/training.json")).unwrap();
    for f in fixtures {
        let id = f["scramble_type_id"].as_str().unwrap();
        let seed = f["seed"].as_u64().unwrap() as u32;
        let generated = generate_training(id, seed, &Default::default()).unwrap();
        assert_eq!(generated.state, f["state"], "{id}/{seed}");
        assert_eq!(generated.case_id, f["case_id"].as_str().map(str::to_owned));
    }
}
#[test]
fn case_selection_and_orientation() {
    for (id, meta) in type_catalog().as_object().unwrap() {
        if meta["kind"] == "official" {
            continue;
        }
        let cases = cases(id);
        if let Some(case) = cases.last() {
            let options = TrainingOptions {
                enabled_case_ids: Some(vec![case.id.clone()]),
                natural: true,
                ..Default::default()
            };
            let result = generate_training(id, 19, &options).unwrap();
            assert_eq!(result.case_id.as_deref(), Some(case.id.as_str()));
        }
    }
    for (id, bottom) in [
        ("333.pll", "white"),
        ("222.eg1", "red"),
        ("skewb.l2l", "blue"),
    ] {
        let orientation = Orientation {
            bottom_color: bottom.into(),
            front_color: None,
        };
        let result = generate_training(
            id,
            0,
            &TrainingOptions {
                orientation: Some(orientation),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(result.orientation.unwrap().bottom_color, bottom);
    }
    for id in ["minx.lsll.invalid", "444.unknown", "pyram.invalid"] {
        assert!(generate_training(id, 0, &Default::default()).is_err());
    }
    assert!(
        generate_training(
            "333.pll",
            0,
            &TrainingOptions {
                enabled_case_ids: Some(vec![]),
                ..Default::default()
            }
        )
        .is_err()
    );
    assert!(
        generate_training(
            "333.pll",
            0,
            &TrainingOptions {
                orientation: Some(Orientation {
                    bottom_color: "white".into(),
                    front_color: Some("yellow".into())
                }),
                ..Default::default()
            }
        )
        .is_err()
    );
}
