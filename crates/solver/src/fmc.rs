//! FMC normalization, OBTM/ETM counting and inverse-prefix checks (legacy 79a1e4c).
use cubegin_puzzle::events::EventState;
use serde::Serialize;
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Validation {
    pub raw_solution: String,
    pub normalized_solution: Option<String>,
    pub move_count: Option<usize>,
    pub execution_move_count: Option<usize>,
    pub status: String,
    pub reason: Option<String>,
    pub inverse_match_length: usize,
}
fn normalize(input: &str) -> Option<Vec<String>> {
    input
        .split_whitespace()
        .map(|t| {
            let (base, suffix) = if let Some(b) = t.strip_suffix("2'") {
                (b, "2")
            } else if let Some(b) = t.strip_suffix('2') {
                (b, "2")
            } else if let Some(b) = t.strip_suffix('\'') {
                (b, "'")
            } else {
                (t, "")
            };
            let lower = base.to_ascii_lowercase();
            let out = if ["x", "y", "z"].contains(&lower.as_str()) {
                lower
            } else {
                let wide = lower.ends_with('w');
                let face = if wide {
                    lower
                        .trim_end_matches('w')
                        .strip_prefix('2')
                        .unwrap_or(lower.trim_end_matches('w'))
                } else {
                    &lower
                };
                if face.len() != 1 || !"rufldb".contains(face) {
                    return None;
                }
                format!("{}{}", face.to_uppercase(), if wide { "w" } else { "" })
            };
            Some(format!("{out}{suffix}"))
        })
        .collect()
}
pub fn validate_fmc(scramble: &str, solution: &str) -> Validation {
    let syntax = || Validation {
        raw_solution: solution.into(),
        normalized_solution: None,
        move_count: None,
        execution_move_count: None,
        status: "dnf".into(),
        reason: Some("syntax".into()),
        inverse_match_length: 0,
    };
    let (Some(s), Some(m)) = (normalize(scramble), normalize(solution)) else {
        return syntax();
    };
    if m.is_empty() {
        return syntax();
    }
    if EventState::solved("333")
        .unwrap()
        .apply(&s.join(" "))
        .is_err()
        || EventState::solved("333")
            .unwrap()
            .apply(&m.join(" "))
            .is_err()
    {
        return syntax();
    }
    let inverse = s
        .iter()
        .rev()
        .map(|t| {
            if t.ends_with('2') {
                t.clone()
            } else if t.ends_with('\'') {
                t[..t.len() - 1].into()
            } else {
                format!("{t}'")
            }
        })
        .collect::<Vec<String>>();
    let prefix = m.iter().zip(&inverse).take_while(|(a, b)| a == b).count();
    let mut v = Validation {
        raw_solution: solution.into(),
        normalized_solution: Some(m.join(" ")),
        move_count: Some(m.iter().filter(|t| !t.starts_with(['x', 'y', 'z'])).count()),
        execution_move_count: Some(m.len()),
        status: "valid".into(),
        reason: None,
        inverse_match_length: prefix,
    };
    let reason = if m.len() > 80 {
        Some("over-80-etm")
    } else if !EventState::solved("333")
        .unwrap()
        .apply(&format!("{} {}", s.join(" "), m.join(" ")))
        .unwrap()
        .is_solved()
    {
        Some("unsolved")
    } else if m == inverse {
        Some("inverse-scramble")
    } else if prefix >= 4 {
        v.status = "suspected-inverse".into();
        v.reason = Some("inverse-scramble".into());
        return v;
    } else {
        None
    };
    if let Some(r) = reason {
        v.status = "dnf".into();
        v.reason = Some(r.into());
    }
    v
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn adjudication() {
        assert_eq!(
            validate_fmc("R U", "U' R'").reason.as_deref(),
            Some("inverse-scramble")
        );
        assert_eq!(validate_fmc("R", "R R2").status, "valid");
        assert_eq!(validate_fmc("R", "U").reason.as_deref(), Some("unsolved"));
        assert_eq!(validate_fmc("R", "M").reason.as_deref(), Some("syntax"));
        assert_eq!(validate_fmc("R", "X x' R R2").move_count, Some(2));
    }
}
