import io.gatling.core.Predef._
import io.gatling.http.Predef._
import scala.concurrent.duration._

class GatlingSimulation extends Simulation {

  val vus = Integer.getInteger("vus", 20)
  val duration = Integer.getInteger("duration", 10)
  val targethost = System.getProperty("targethost")
  val targetpath = System.getProperty("targetpath")
  val targetproto = System.getProperty("targetproto")

  val httpConf = http
    .baseUrl(targetproto + "://" + targethost) // Here is the root for all relative URLs
    .disableCaching

//    .acceptHeader("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8") // Here are the common headers
//    .doNotTrackHeader("1")
//    .acceptLanguageHeader("en-US,en;q=0.5")
//    .acceptEncodingHeader("gzip, deflate")
//    .userAgentHeader("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:16.0) Gecko/20100101 Firefox/16.0")

//  val headers_10 = Map("Content-Type" -> "application/x-www-form-urlencoded") // Note the headers specific to a given request

  val scn = scenario("Scenario Name") // A scenario is a chain of requests and pauses
    .during (duration) {
      exec(http("request_1").get(targetpath))
    }
  setUp(scn.inject(atOnceUsers(vus)).protocols(httpConf))
}

