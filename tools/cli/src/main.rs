const USAGE: &str = "cubegin events|types|methods|version
  cases <type>
  event-evaluate|event-inverse|event-solve|event-timeline|player <event> <algorithm>
  event-scramble <event> <seed>
  training <type> <seed> [options-json]
  batch <type> <seed> <count> [options-json]
  multiblind <seed> <cube-count>
  assist <event> <comma-separated-methods> <algorithm> [options-json]
  player-svg <event> <algorithm> <completed> <progress>
  fmc <scramble> <solution>
  evaluate|inverse|timeline <3x3-outer-turn-algorithm>
  solve|render <URFDLB-facelets> / scramble <seed>";
fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_else(|| "help".into());
    let input = args.next().unwrap_or_default();
    match command.as_str() {
        "help" | "--help" | "-h" => println!("{USAGE}"),
        "methods" => println!("{}", serde_json::to_string(&cubegin::events::METHODS)?),
        "fmc" => println!(
            "{}",
            serde_json::to_string(&cubegin::events::validate_fmc(
                &input,
                &args.next().unwrap_or_default()
            ))?
        ),
        "event-inverse" => println!(
            "{}",
            cubegin::events::inverse_event(&input, &args.next().unwrap_or_default())?
        ),
        "event-timeline" => println!(
            "{}",
            serde_json::to_string(&cubegin::events::timeline_event(
                &input,
                &args.next().unwrap_or_default()
            )?)?
        ),
        "player-svg" => {
            let algorithm = args.next().unwrap_or_default();
            let completed = args.next().unwrap_or_default().parse()?;
            let progress = args.next().unwrap_or_default().parse()?;
            println!(
                "{}",
                cubegin::events::player_svg(&input, &algorithm, completed, progress)?
            );
        }
        "multiblind" => println!(
            "{}",
            serde_json::to_string(&cubegin::events::generate_multi_blind(
                input.parse()?,
                args.next().unwrap_or_default().parse()?
            )?)?
        ),
        "batch" => {
            let seed = args.next().unwrap_or_default().parse()?;
            let count = args.next().unwrap_or_default().parse()?;
            let options = serde_json::from_str(&args.next().unwrap_or_else(|| "{}".into()))?;
            println!(
                "{}",
                serde_json::to_string(&cubegin::events::generate_batch(
                    &input, seed, count, &options
                )?)?
            );
        }
        "events" => println!("{}", serde_json::to_string(&cubegin::events::catalog())?),
        "types" => println!("{}", cubegin::events::type_catalog()),
        "cases" => println!(
            "{}",
            serde_json::to_string(&cubegin::events::cases(&input))?
        ),
        "event-evaluate" => println!(
            "{}",
            serde_json::to_string(&cubegin::events::evaluate_event(
                &input,
                &args.next().unwrap_or_default()
            )?)?
        ),
        "event-scramble" => println!(
            "{}",
            serde_json::to_string(&cubegin::events::generate_event(
                &input,
                args.next().unwrap_or_default().parse()?
            )?)?
        ),
        "event-solve" => println!(
            "{}",
            cubegin::events::solve_event(&input, &args.next().unwrap_or_default())?
        ),
        "training" => println!(
            "{}",
            serde_json::to_string(&cubegin::events::generate_training(
                &input,
                args.next().unwrap_or_default().parse()?,
                &serde_json::from_str(&args.next().unwrap_or_else(|| "{}".into()))?
            )?)?
        ),
        "assist" => {
            let methods = args
                .next()
                .unwrap_or_default()
                .split(',')
                .map(str::to_owned)
                .collect::<Vec<_>>();
            let algorithm = args.next().unwrap_or_default();
            println!(
                "{}",
                serde_json::to_string(&cubegin::events::solve_assist(
                    &input,
                    &methods,
                    &algorithm,
                    &serde_json::from_str(&args.next().unwrap_or_else(|| "{}".into()))?
                )?)?
            );
        }
        "player" => println!(
            "{}",
            serde_json::to_string(&cubegin::events::player_timeline(
                &input,
                &args.next().unwrap_or_default()
            )?)?
        ),
        "evaluate" => println!("{}", serde_json::to_string(&cubegin::evaluate(&input)?)?),
        "solve" => println!("{}", cubegin::solve(&input)?),
        "inverse" => println!("{}", cubegin::inverse(&input)?),
        "scramble" => println!(
            "{}",
            serde_json::to_string(&cubegin::scramble(input.parse()?)?)?
        ),
        "render" => println!("{}", cubegin::render(&input)?),
        "timeline" => println!(
            "{}",
            serde_json::to_string(&cubegin::timeline(&cubegin::Cube::default(), &input)?)?
        ),
        "version" => println!("{}", cubegin::VERSION),
        _ => return Err(USAGE.into()),
    }
    Ok(())
}
