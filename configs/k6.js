import http from "k6/http";

export default function() {
  for (var i = 0; i < REQS_PER_VU; i++) {
    http.get("TARGETURL");
  }
};
