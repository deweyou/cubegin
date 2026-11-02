fn main() {
    let maps = ["U", "D", "F", "B", "L", "R", "BL", "BR"]
        .map(|g| tnoodle_backend::puzzle::FtoState::move_permutation(g).unwrap());
    println!("{}", serde_json::to_string(&maps).unwrap());
}
