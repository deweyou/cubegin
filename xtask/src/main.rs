use std::process::{Command, Stdio};
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap();
    std::env::set_current_dir(root).unwrap();
    if let Err(e) = run() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
fn command(program: &str, args: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
    eprintln!("{program} {}", args.join(" "));
    if !Command::new(program)
        .args(args)
        .stdin(Stdio::inherit())
        .status()?
        .success()
    {
        return Err(format!("{program} failed").into());
    }
    Ok(())
}
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    match args.first().map(String::as_str) {
        Some("check")=> {
            command("node", &["--test","scripts/artifact-metadata.test.mjs"])?;
            for fixture in ["states.json", "events.json"] {
                if std::fs::read(format!("fixtures/{fixture}"))? != std::fs::read(format!("crates/puzzle/tests/fixtures/{fixture}"))? {
                    return Err(format!("packaged {fixture} differs from shared SDK fixtures").into());
                }
            }
            for member in ["puzzle", "solver", "scramble", "diagram", "playback", "cubegin"] {
                for asset in ["LICENSE", "NOTICE"] {
                    if std::fs::read(asset)? != std::fs::read(format!("crates/{member}/{asset}"))? {
                        return Err(format!("crates/{member}/{asset} differs from root {asset}").into());
                    }
                }
            }
            command("cargo", &["fmt","--all","--","--check"])?;
            command("cargo", &["clippy","--workspace","--all-targets","--locked","--","-D","warnings"])?;
            command("cargo", &["test","--workspace","--locked"])?;
        }
        Some("build-sdk")=> {
            match args.get(1).map(String::as_str) {
                Some("web")=>command("node", &["scripts/build-web.mjs"])?,
                Some("native")=>command("node", &["scripts/build-native.mjs"])?,
                Some("ios")=>command("node", &["scripts/build-ios.mjs"])?,
                Some("android")=>command("node", &["scripts/build-android.mjs"])?,
                _=>return Err("specify a platform: web, native (host bindings), ios, or android".into()),
            }
        }
        Some("verify-packages")=>command("node", &["scripts/verify-packages.mjs"])?,
        Some("verify-rust-packages")=>command("node", &["scripts/verify-rust-packages.mjs"])?,

        Some("release")=> {
            if args.len()!=4 || args[1]!="--version" || args[3]!="--dry-run" { return Err("only release --version <version> --dry-run is supported; publication is not wired".into()); }
            command("node", &["scripts/release.mjs",&args[2]])?;
        }
        _=>return Err("usage: cargo xtask check | build-sdk <web|native|ios|android> | verify-packages | verify-rust-packages | release --version <version> --dry-run".into()),
    }
    Ok(())
}
