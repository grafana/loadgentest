from locust import HttpLocust, TaskSet

def stylesheet(l):
    for i in range(100):
      l.client.get("TARGETPATH")

class UserBehavior(TaskSet):
    tasks = {stylesheet:1}

class WebsiteUser(HttpLocust):
    task_set = UserBehavior
