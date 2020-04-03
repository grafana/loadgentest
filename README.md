# loadgentest

Lab environment for benchmarking different load testing tools: 
- ApacheBench
- Artillery
- Gatling
- Hey 
- JMeter
- k6 
- Locust
- Siege
- Tsung
- Vegeta
- wrk


## Instructions

```bash
git clone https://github.com/loadimpact/loadgentest
cd loadgentest
./runtests.sh
```

## Notes

In 2017, a [blog post](https://k6.io/blog/ref-open-source-load-testing-tool-benchmarks-v2) published the benchmark results of the different tools.

Later in 2020, a new [blog post](https://k6.io/blog/comparing-best-open-source-load-testing-tools) updated the previous benchmarks and comparative. But the `loadgentest` project was not used to report the new benchmarks.
