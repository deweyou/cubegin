fn main() {
    let mut results = Vec::new();
    for (event, method) in cubegin_solver::assist::METHODS {
        let algorithm = match *event {
            "333" => "R U2 F' L2 D B R2 F2 U' L D2 B'",
            "222" => "R U F",
            "pyram" => "R U L",
            "skewb" => "R U B",
            "sq1" => "(1,0) / (0,3) /",
            _ => unreachable!(),
        };
        eprintln!("start {event} {method}");
        let start = std::time::Instant::now();
        match cubegin_solver::assist::solve_assist(
            event,
            &[method.to_string()],
            algorithm,
            &Default::default(),
        ) {
            Ok(r) => {
                eprintln!(
                    "pass {method} {} {}ms",
                    r[0].solutions.len(),
                    start.elapsed().as_millis()
                );
                results.extend(r)
            }
            Err(e) => eprintln!("FAIL {method} {e}"),
        }
    }
    println!("{}", serde_json::to_string(&results).unwrap());
}
