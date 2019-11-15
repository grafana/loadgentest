from locust import TaskSet, task, constant
from locust.contrib.fasthttp import FastHttpLocust


class UserBehavior(TaskSet):
    @task
    def bench_task(self):
        while True:
            self.client.get("TARGETPATH")

class WebsiteUser(FastHttpLocust):
    task_set = UserBehavior
    wait_time = constant(0)
