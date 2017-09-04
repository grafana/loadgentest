import http from "k6/http";

export default function() {
  for (var i = 0; i <= (REQS_PER_VU/100); i++) {
    http.get("TARGETURL");
  }
};
