use super::{SvgSurface, Vector};

/// Clock artwork lies on parallel planes. Their order along a viewing ray is
/// determined by their height above the board, even when their centers are
/// far apart horizontally. The rim spans the gap between the two faces.
pub(super) fn sort_clock(polygons: &mut Vec<SvgSurface>, board_normal: Vector) {
    let edge_on = board_normal.z.abs() < 1e-10;
    polygons.retain(|surface| !edge_on || surface.sticker_id.starts_with("clock-board-rim-"));
    polygons.sort_by_cached_key(|surface| {
        if surface.sticker_id.starts_with("clock-board-rim-") {
            let depth =
                surface.vertices.iter().map(|v| v.z).sum::<f64>() / surface.vertices.len() as f64;
            return (0, quantize(depth));
        }

        let v = surface.vertices[0];
        let height = v.x * board_normal.x + v.y * board_normal.y + v.z * board_normal.z;
        (quantize(height * board_normal.z.signum()), 0)
    });
}

// Rotating a rigid model can introduce slightly different rounding errors at
// different points in the same plane. Preserve model order for those ties.
fn quantize(depth: f64) -> i64 {
    (depth * 1e9).round() as i64
}
