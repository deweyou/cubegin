use cubegin_solver::assist::*;
use serde_json::Value;
#[test]
fn legacy_certified_auxiliary_solutions() {
    let fixtures: Vec<Value> = serde_json::from_str(include_str!("fixtures/assist.json")).unwrap();
    for f in fixtures {
        let method = f["method"].as_str().unwrap();
        let event = METHODS.iter().find(|(_, m)| *m == method).unwrap().0;
        let algorithm = f["scramble"].as_str().unwrap();
        let result = solve_assist(event, &[method.into()], algorithm, &Default::default()).unwrap();
        assert_eq!(
            serde_json::to_value(&result[0]).unwrap(),
            f,
            "{event}/{method}"
        );
    }
}
#[test]
fn reject_invalid_requests() {
    assert!(solve_assist("222", &["cross".into()], "R", &Default::default()).is_err());
    assert!(solve_assist("333", &["cross".into()], "?", &Default::default()).is_err());
    assert!(
        solve_assist(
            "333",
            &["cross".into()],
            "R",
            &AssistOptions {
                targets: Some(vec!["bad".into()]),
                ..Default::default()
            }
        )
        .is_err()
    );
}
