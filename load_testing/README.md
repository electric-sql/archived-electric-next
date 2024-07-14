# Load testing

Run load tests against Electric using Locust (https://locust.io/).

# How to run tests

Start Electric and infra.

```bash
HOST=[electric_address] npm run load-test [testname]
```

You can access Locust dashboard at the default bind address (0.0.0.0:8089) and save load test data to `OUTPUT_DIR`. Override global test execution time with `TIME`.

Use util scripts for easy dumping and loading database data for tests.

```bash
export DATABASE_URL="postgres://postgres:password@localhost:54321/electric"

npm run table-load issue ./issue.csv
npm run table-dump issue ./issue.csv
npm run run-sql scripts/linearlite_schema.sql
```

# How to create new tests

Create a [locustfile](https://docs.locust.io/en/stable/writing-a-locustfile.html) under ```scripts/[testname]```:

```python
class ElectricClient(HttpUser):
    wait_time = constant_pacing(1)

    shape_name = "issue"
    base_url = "/shape/"+shape_name
    
    shape_size = 0
    num_shapes = 0

    ...
    
    @task
    def live_mode(self):
        query_params = self.query_params

        encoded_params = urllib.parse.urlencode(query_params)
        res = self.client.get(self.base_url + '?' + encoded_params)

        if res.status_code != 200 and res.status_code != 204:
            logging.error('request failed')
            return
```

And the configurations for the test:

```javascript
[
  {
    "users": 10000,
    "rate": 5,
    "config": {
      "user_class_name": "ElectricClient",
      "shape_size": 1,
      "num_shapes": 100
    }
  },  
]
```

# TODO
- Distribution