import Foundation
import Cubegin
struct Fixture:Decodable { let algorithm:String;let facelets:String }
func require(_ value:Bool,_ message:String) throws { if !value { throw NSError(domain:message,code:1) } }
let data=try Data(contentsOf:URL(fileURLWithPath:"fixtures/states.json"))
let fixtures=try JSONDecoder().decode([Fixture].self,from:data)
for fixture in fixtures {
 let snapshot=try evaluate(algorithm:fixture.algorithm)
 try require(snapshot.facelets==fixture.facelets,"fixture mismatch: \(fixture.algorithm)")
}
do { _=try evaluate(algorithm:"Rw");fatalError("invalid notation accepted") } catch is CubeginError {}
do { _=try solve(facelets:"bad");fatalError("invalid state accepted") } catch is CubeginError {}
let generated=try scramble(seed:42)
let solution=try solve(facelets:generated.facelets)
let restored=try evaluate(algorithm:generated.algorithm+" "+solution)
try require(restored.solved,"solution replay failed")
let steps=try timeline(algorithm:"R U2 F'")
let expected=try evaluate(algorithm:"R U2 F'")
try require(steps.last?.after==expected.facelets,"timeline mismatch")
print("Swift native SDK: \(fixtures.count) shared fixtures, errors, scramble, solve and timeline passed")
// Foundation JSON comparison avoids assuming all puzzles share one topology.
let eventsData = try Data(contentsOf: URL(fileURLWithPath: "fixtures/events.json"))
guard let eventFixtures = try JSONSerialization.jsonObject(with: eventsData) as? [[String: Any]] else {
    throw NSError(domain: "Invalid event fixture list", code: 1)
}
for fixture in eventFixtures {
    guard let eventID = fixture["eventId"] as? String,
          let algorithm = fixture["algorithm"] as? String,
          let state = fixture["state"] as? [AnyHashable: Any] else {
        throw NSError(domain: "Invalid event fixture", code: 1)
    }
    let snapshot = try evaluateEvent(event: eventID, algorithm: algorithm)
    let actual = try JSONSerialization.jsonObject(with: Data(snapshot.stateJson.utf8)) as? NSDictionary
    try require(actual?.isEqual(to: state) == true, "event fixture mismatch")
}
let training=try generateTraining(id:"333.pll",seed:42,optionsJson:"{}")
try require(training.contains("333.pll"),"training result missing")
let assist=try solveAssist(event:"333",methodsJson:"[\"cross\"]",algorithm:"R U F",optionsJson:"{}")
try require(assist.contains("solution"),"assist missing")
let frame=try playerSvg(event:"sq1",algorithm:"(1,0) /",completed:1,progress:0.5)
try require(frame.contains("<polygon"),"player missing")
print("Swift expanded SDK: \(eventFixtures.count) multi-puzzle state fixtures, training, assist and player passed")
