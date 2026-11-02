fn main() {
    let catalog: serde_json::Value =
        serde_json::from_str(include_str!("../data/catalog.json")).unwrap();
    let mut results = Vec::new();
    for (id, info) in catalog.as_object().unwrap() {
        if info["kind"] == "official" {
            continue;
        }
        let start = std::time::Instant::now();
        eprintln!("start {id}");
        let result = std::panic::catch_unwind(|| {
            cubegin_scramble::training::generate_training(
                id,
                std::env::args()
                    .nth(1)
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(42),
                &Default::default(),
            )
        });
        match result {
            Ok(Ok(s)) => {
                eprintln!("pass {id} {}ms", start.elapsed().as_millis());
                results.push(serde_json::to_value(s).unwrap());
            }
            Ok(Err(e)) => {
                eprintln!("FAIL {id}: {e}");
                results.push(serde_json::json!({"scramble_type_id":id,"error":e.to_string()}));
            }
            Err(_) => {
                results.push(serde_json::json!({"scramble_type_id":id,"error":"panic"}));
            }
        }
    }
    println!("{}", serde_json::to_string(&results).unwrap());
}
