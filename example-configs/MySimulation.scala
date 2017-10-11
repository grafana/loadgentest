import io.gatling.core.Predef._
import io.gatling.http.Predef._
import scala.concurrent.duration._

class MySimulation extends Simulation {

  val httpConf = http
    .baseURL("http://test.loadimpact.com") // Here is the root for all relative URLs
    .disableCaching

  val scn = scenario("Scenario Name") // A scenario is a chain of requests and pauses
    .during (10) {
      exec(http("request_1").get("/"))
    }
  setUp(scn.inject(atOnceUsers(10)).protocols(httpConf))
}

