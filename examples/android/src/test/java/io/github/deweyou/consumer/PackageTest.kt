package io.github.deweyou.consumer
import io.github.deweyou.cubegin.*
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONArray
class PackageTest {
 @Test fun stagedMavenArtifact() {
  val cases=JSONArray(javaClass.classLoader!!.getResource("states.json")!!.readText())
  for(i in 0 until cases.length()) {
   val f=cases.getJSONObject(i)
   assertEquals(f.getString("facelets"),evaluate(f.getString("algorithm")).facelets)
  }
  val s=scramble(42u)
  assertTrue(evaluate(s.algorithm+" "+solve(s.facelets)).solved)
 }
 @Test fun expandedCapabilities(){
  assertTrue(evaluateEvent("444","Rw U").svg.contains("svg"))
  assertTrue(generateTraining("333.pll",42u,"{}").contains("333.pll"))
  assertTrue(solveAssist("333","[\"cross\"]","R U F","{}").contains("solution"))
  assertTrue(playerSvg("sq1","(1,0) /",1u,0.5).contains("<polygon"))
 }
}
