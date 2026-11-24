//! Paint Square-1's layered stickers and cut faces in true visibility order.
use super::{SvgSurface, Vector};

const EPSILON: f64 = 1e-9;

fn dot(a: Vector, b: Vector) -> f64 {
    a.x * b.x + a.y * b.y + a.z * b.z
}

fn area_vector(vertices: &[Vector]) -> Vector {
    let mut area = Vector {
        x: 0.,
        y: 0.,
        z: 0.,
    };
    let origin = vertices[0].scale(-1.);
    let mut previous = vertices[1].add(origin);
    for vertex in &vertices[2..] {
        let v = vertex.add(origin);
        area.x += previous.y * v.z - previous.z * v.y;
        area.y += previous.z * v.x - previous.x * v.z;
        area.z += previous.x * v.y - previous.y * v.x;
        previous = v;
    }
    area
}

pub(super) fn sort_square1(polygons: &mut Vec<SvgSurface>) {
    enum Work {
        Partition(Vec<SvgSurface>),
        Emit(Vec<SvgSurface>),
    }
    let mut work = vec![Work::Partition(std::mem::take(polygons))];
    while let Some(item) = work.pop() {
        match item {
            Work::Emit(mut faces) => polygons.append(&mut faces),
            Work::Partition(mut faces) if faces.len() <= 1 => polygons.append(&mut faces),
            Work::Partition(faces) => {
                if let Some((behind, plane, ahead)) = partition(faces) {
                    work.push(Work::Partition(ahead));
                    work.push(Work::Emit(plane));
                    work.push(Work::Partition(behind));
                }
            }
        }
    }
}

type Partition = (Vec<SvgSurface>, Vec<SvgSurface>, Vec<SvgSurface>);

// Partition by an actual face plane. A centroid alone cannot order an inset
// sticker against its larger backing once the layer tilts toward the viewer.
fn partition(input: Vec<SvgSurface>) -> Option<Partition> {
    let (index, area) = input
        .iter()
        .enumerate()
        .map(|(i, face)| (i, area_vector(&face.vertices)))
        .max_by(|(_, a), (_, b)| a.z.abs().total_cmp(&b.z.abs()))
        .unwrap();
    if area.z.abs() < EPSILON {
        return None;
    }
    let normal = area.norm().scale(area.z.signum());
    let offset = dot(normal, input[index].vertices[0]);
    let distance = |p| dot(normal, p) - offset;
    let (mut behind, mut plane, mut ahead) = (Vec::new(), Vec::new(), Vec::new());
    for (i, face) in input.into_iter().enumerate() {
        // A narrow fragment can lose enough numerical precision to classify
        // itself on one side. Consume the splitter even in that case.
        if i == index {
            plane.push(face);
            continue;
        }
        let back = face.vertices.iter().any(|&v| distance(v) < -EPSILON);
        let front = face.vertices.iter().any(|&v| distance(v) > EPSILON);
        match (back, front) {
            (true, false) => behind.push(face),
            (false, true) => ahead.push(face),
            (false, false) => plane.push(face),
            (true, true) => {
                let (mut left, mut right) = (Vec::new(), Vec::new());
                let mut last = *face.vertices.last().unwrap();
                for &v in &face.vertices {
                    let (a, b) = (distance(last), distance(v));
                    if (a < -EPSILON && b > EPSILON) || (a > EPSILON && b < -EPSILON) {
                        let cut = last.add(v.add(last.scale(-1.)).scale(a / (a - b)));
                        left.push(cut);
                        right.push(cut);
                    }
                    if b <= EPSILON {
                        left.push(v);
                    }
                    if b >= -EPSILON {
                        right.push(v);
                    }
                    last = v;
                }
                behind.push(SvgSurface {
                    vertices: left,
                    color: face.color.clone(),
                    sticker_id: face.sticker_id.clone(),
                });
                ahead.push(SvgSurface {
                    vertices: right,
                    ..face
                });
            }
        }
    }
    Some((behind, plane, ahead))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn face(id: &str, points: &[(f64, f64, f64)]) -> SvgSurface {
        SvgSurface {
            vertices: points.iter().map(|&(x, y, z)| Vector { x, y, z }).collect(),
            sticker_id: id.to_owned(),
            color: String::new(),
        }
    }

    #[test]
    fn a_twisted_splitter_is_emitted_once() {
        let edge = face(
            "edge",
            &[(0., 0., 0.), (2., 0., 0.01), (2., 2., 0.), (0., 2., 0.01)],
        );
        let cap = face("cap", &[(0., 0., 1.), (1., 0., 1.), (0., 1., 1.)]);
        let mut faces = vec![edge, cap];
        sort_square1(&mut faces);
        assert_eq!(faces.len(), 2);
        assert_eq!(faces[0].sticker_id, "edge");
    }

    #[test]
    fn tilted_sticker_stays_in_front_of_its_larger_backing() {
        // The sticker is 0.01 above the backing at every shared pixel, but its
        // smaller outline puts its centroid farther from the camera.
        let sticker = face(
            "sticker",
            &[
                (0., 0., 0.01),
                (1., 0., 1.01),
                (1., 1., 1.01),
                (0., 1., 0.01),
            ],
        );
        let backing = face(
            "backing",
            &[(0., 0., 0.), (3., 0., 3.), (3., 1., 3.), (0., 1., 0.)],
        );
        let mut faces = vec![sticker, backing];
        sort_square1(&mut faces);
        assert_eq!(
            faces
                .iter()
                .map(|f| f.sticker_id.as_str())
                .collect::<Vec<_>>(),
            ["backing", "sticker"]
        );
    }
}
