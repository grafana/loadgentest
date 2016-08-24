class MySimulation extends Simulation {
  val httpConf = http
    .baseURL("http://TARGETHOST") // Here is the root for all relative URLs
    .disableCaching
  val scn = scenario("Scenario Name") // A scenario is a chain of requests and pauses
    .forever (
      exec(http("request_1").get("TARGETPATH"))
    )
  setUp(scn.inject(atOnceUsers(20)).protocols(httpConf))
