fn main() {
    use tnoodle_backend::fto3phase::{FtoCubie, moves::*};
    let data=[U,D,F,B,L,R,BL,BR].map(|g|{let c=FtoCubie::coordinate_move(g);serde_json::json!({"cp":c.corner_perm(),"co":c.corner_ori(),"ep":c.edges(),"uf":c.triangles_ufbrbl(),"rl":c.triangles_rlbd()})});
    println!("{}", serde_json::to_string(&data).unwrap());
}
