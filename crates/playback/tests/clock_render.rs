use cubegin_playback::player::{CameraOffset, player_frame, player_svg_with_camera};

// Sample the actual painted SVG in document order, including occlusion by
// later surfaces. Counting dial polygons alone would miss an obscured dial.
fn color_at(svg: &str, x: f64, y: f64) -> Option<&str> {
    svg.rsplit("<polygon points=\"")
        .take_while(|part| !part.starts_with("<svg"))
        .find_map(|polygon| {
            let (points, rest) = polygon.split_once("\" fill=\"").unwrap();
            let vertices: Vec<(f64, f64)> = points
                .split_whitespace()
                .map(|point| {
                    let (x, y) = point.split_once(',').unwrap();
                    (x.parse().unwrap(), y.parse().unwrap())
                })
                .collect();
            let inside = vertices
                .iter()
                .zip(vertices.iter().cycle().skip(1))
                .filter(|&(&(ax, ay), &(bx, by))| {
                    (ay > y) != (by > y) && x < ax + (y - ay) * (bx - ax) / (by - ay)
                })
                .count()
                % 2
                == 1;
            inside.then(|| rest.split_once('"').unwrap().0)
        })
}

#[test]
fn all_nine_clock_dials_remain_visible_during_a_flip_and_orbit() {
    let model = player_frame("clock", "", 0, 0.).unwrap();
    let scale = 400. / model["cameraDistance"].as_f64().unwrap();
    for (flip, progress, orbit) in [
        ("y2", 0.32, 0.),
        ("y2", 0.68, 0.),
        ("y2", 0., -0.9),
        ("y2", 1., -0.9),
        ("x2", 0.32, 0.),
        ("x2", 0.68, 0.),
    ] {
        let angle = progress * std::f64::consts::PI - orbit;
        let front = angle.cos() > 0.;
        let side = if front { 1. } else { -1. };
        let svg = player_svg_with_camera(
            "clock",
            flip,
            0,
            progress,
            CameraOffset {
                yaw: orbit,
                pitch: 0.,
            },
        )
        .unwrap();
        for row in -1..=1 {
            for column in -1..=1 {
                // A point on the dial face clear of its hand, hub and ticks.
                let dial_x = f64::from(column) * 0.78 + 0.10;
                let dial_y = f64::from(row) * 0.78 - 0.10;
                let (projected_x, projected_y) = if flip == "y2" {
                    (dial_x * angle.cos() + side * 0.149 * angle.sin(), dial_y)
                } else {
                    (dial_x, dial_y * angle.cos() + side * 0.149 * angle.sin())
                };
                assert_eq!(
                    color_at(&svg, 150. + projected_x * scale, 150. - projected_y * scale),
                    Some(if front { "#ccddee" } else { "#113366" }),
                    "dial ({column}, {row}), {flip} at {progress}, orbit {orbit}"
                );
            }
        }
    }
}
