use cubegin_puzzle::{Cube, FACES};
pub const COLORS: [&str; 6] = [
    "#ffffff", "#d93636", "#159957", "#ffd633", "#ff8a24", "#2962d9",
];
/// Fixed 12x9-unit cube net. All sticker IDs use URFDLB row-major indices.
pub fn render(cube: &Cube) -> String {
    let offsets = [(3, 0), (6, 3), (3, 3), (3, 6), (0, 3), (9, 3)];
    let mut svg = String::from(
        r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 12 9" role="img" aria-label="3 by 3 cube net"><g stroke="#172026" stroke-width="0.035">"##,
    );
    for (index, color) in cube.facelets().bytes().enumerate() {
        let (x, y) = offsets[index / 9];
        let fill = COLORS[FACES.iter().position(|f| *f == color).unwrap()];
        svg.push_str(&format!(r#"<rect data-sticker="{index}" x="{}" y="{}" width="0.94" height="0.94" rx="0.04" fill="{fill}"/>"#,x+index%3,y+index%9/3));
    }
    svg.push_str("</g></svg>");
    svg
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn renders_all_stickers() {
        let svg = render(&Cube::default().apply("R U").unwrap());
        assert_eq!(svg.matches("<rect ").count(), 54);
        for i in 0..54 {
            assert!(svg.contains(&format!("data-sticker=\"{i}\"")));
        }
        for color in COLORS {
            assert_eq!(svg.matches(color).count(), 9);
        }
    }
}
