import io.github.deweyou.cubegin.*
import java.io.File
fun main(args:Array<String>) {
 val fixtures=File(args[0]).readLines()
 for(line in fixtures) {
  val parts=line.split('\t')
  check(evaluate(parts[0]).facelets==parts[1]) { "fixture mismatch: ${parts[0]}" }
 }
 try { evaluate("Rw");error("accepted invalid notation") } catch(_:CubeginException) {}
 try { solve("bad");error("accepted invalid state") } catch(_:CubeginException) {}
 val s=scramble(42u)
 check(evaluate(s.algorithm+" "+solve(s.facelets)).solved)
 check(timeline("R U2 F'").last().after==evaluate("R U2 F'").facelets)
 println("Kotlin/JNA host SDK: ${fixtures.size} shared fixtures, errors, scramble, solve and timeline passed")
 val events=File("target/kotlin-test/events.tsv").readLines()
 for(line in events){val parts=line.split('\t');check(evaluateEvent(parts[0],parts[1]).stateJson==parts[2]) { "event mismatch: ${parts[0]} ${parts[1]}" }}
 check(generateTraining("333.pll",42u,"{}").contains("333.pll"))
 check(solveAssist("333","[\"cross\"]","R U F","{}").contains("solution"))
 check(playerSvg("sq1","(1,0) /",1u,0.5).contains("<polygon"))
 println("Kotlin expanded SDK: ${events.size} multi-puzzle fixtures, training, assist and player passed")
}
