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
/// Fit a generated event SVG to its artwork with one SVG unit of padding.
pub fn trim_event_svg(mut svg: String) -> String {
    let Ok(document) = usvg::roxmltree::Document::parse(&svg) else {
        return svg;
    };
    let Ok(tree) = usvg::Tree::from_xmltree(&document, &usvg::Options::default()) else {
        return svg;
    };
    // Event SVGs use a zero-origin viewBox matching their intrinsic dimensions.
    // Labels in the Megaminx renderer are inside the sticker outlines.
    let bounds = tree.root().abs_stroke_bounding_box();
    if bounds.width() <= 0.0 || bounds.height() <= 0.0 {
        return svg;
    }
    let x = f64::from(bounds.left()) - 1.0;
    let y = f64::from(bounds.top()) - 1.0;
    let width = f64::from(bounds.width()) + 2.0;
    let height = f64::from(bounds.height()) + 2.0;
    let root = document.root_element();
    let mut replacements: Vec<_> = [
        ("width", width.to_string()),
        ("height", height.to_string()),
        ("viewBox", format!("{x} {y} {width} {height}")),
    ]
    .into_iter()
    .filter_map(|(name, value)| Some((root.attribute_node(name)?.range_value(), value)))
    .collect();
    if replacements.len() == 3 {
        replacements.sort_unstable_by_key(|(range, _)| std::cmp::Reverse(range.start));
        for (range, value) in replacements {
            svg.replace_range(range, &value);
        }
    }
    svg
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn event_diagrams_have_one_unit_of_padding() {
        use cubegin_puzzle::events::{EventState, catalog};

        for (event, algorithm) in catalog()
            .iter()
            .map(|event| (event.id.as_str(), ""))
            .chain([("sq1", "(3,0) /")])
        {
            let svg = EventState::solved(event)
                .unwrap()
                .apply(algorithm)
                .unwrap()
                .svg(event)
                .unwrap();
            let cropped = trim_event_svg(svg);
            let tree = usvg::Tree::from_str(&cropped, &usvg::Options::default()).unwrap();
            let bounds = tree.root().abs_stroke_bounding_box();
            for margin in [
                bounds.left(),
                bounds.top(),
                tree.size().width() - bounds.right(),
                tree.size().height() - bounds.bottom(),
            ] {
                assert!((margin - 1.0).abs() < 0.01, "{event}: {margin}");
            }
        }
    }

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
