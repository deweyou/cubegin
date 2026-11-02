package io.github.deweyou.cubegin

import org.junit.Test
import org.junit.Assert.*
import org.json.JSONArray
import org.json.JSONObject

class EngineTest {
 @Test fun sharedFixtures() {
  val text=javaClass.classLoader!!.getResource("states.json")!!.readText()
  val fixtures=JSONArray(text)
  for(i in 0 until fixtures.length()) {
   val fixture=fixtures.getJSONObject(i)
   assertEquals(fixture.getString("facelets"),evaluate(fixture.getString("algorithm")).facelets)
  }
 }
 @Test fun allEventFixtures() {
  val fixtures=JSONArray(javaClass.classLoader!!.getResource("events.json")!!.readText())
  for(i in 0 until fixtures.length()) {
   val fixture=fixtures.getJSONObject(i)
   val event=fixture.getString("eventId")
   val algorithm=fixture.getString("algorithm")
   val actual=JSONObject(evaluateEvent(event,algorithm).stateJson)
   assertTrue("Event state mismatch: $event $algorithm",sameJson(fixture.getJSONObject("state"),actual))
  }
 }
 @Test fun errorsAndReplay() {
  assertThrows(CubeginException::class.java) { evaluate("Rw") }
  assertThrows(CubeginException::class.java) { solve("bad") }
  val s=scramble(42u)
  assertTrue(evaluate(s.algorithm+" "+solve(s.facelets)).solved)
  assertEquals(evaluate("R U2 F'").facelets,timeline("R U2 F'").last().after)
 }
 @Test fun expandedCapabilities() {
  assertEquals(18,JSONArray(eventCatalog()).length())
  assertEquals(112,JSONObject(typeCatalog()).length())
  assertEquals(20,JSONArray(assistMethods()).length())
  val training=JSONObject(generateTraining("333.pll",42u,"{}"))
  assertEquals("333.pll",training.getString("scramble_type_id"))
  val evaluated=JSONObject(evaluateEvent("333",training.getString("algorithm")).stateJson)
  assertTrue(sameJson(training.getJSONObject("state"),evaluated))
  assertEquals(6,JSONArray(solveAssist("333","[\"cross\"]","R U F","{}"))
    .getJSONObject(0).getJSONArray("solutions").length())
  assertEquals("valid",JSONObject(validateFmc("R","R R2")).getString("status"))
  assertTrue(playerSvg("sq1","(1,0) /",1u,0.5).contains("<polygon"))
  assertEquals(2,JSONObject(playerTimeline("sq1","(1,0) /")).getJSONArray("steps").length())
  assertThrows(CubeginException::class.java) { generateTraining("unknown",42u,"{}") }
 }
 // Android's org.json compile API lacks JSONObject.similar; compare structurally.
 private fun sameJson(expected:Any?,actual:Any?):Boolean {
  if(expected is JSONObject && actual is JSONObject) {
   val keys=expected.keys().asSequence().toSet()
   return keys==actual.keys().asSequence().toSet() && keys.all { sameJson(expected.get(it),actual.get(it)) }
  }
  if(expected is JSONArray && actual is JSONArray) {
   return expected.length()==actual.length() && (0 until expected.length()).all { sameJson(expected.get(it),actual.get(it)) }
  }
  if(expected is Number && actual is Number)return expected.toDouble()==actual.toDouble()
  return expected==actual
 }
}
