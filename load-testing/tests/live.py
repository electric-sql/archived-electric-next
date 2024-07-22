import logging
import random
import urllib.parse

from locust import HttpUser, task, constant_pacing
    

class ElectricClient(HttpUser):
    wait_time = constant_pacing(1)

    shape_name = "issue"
    base_url = "/v1/shape/"+shape_name
    
    shape_size = 0
    num_shapes = 0

    def on_start(self):
        self.shape_size = ElectricClient.shape_size
        self.num_shapes = ElectricClient.num_shapes

        query_params = {
            'offset': '-1',
        }
        
        encoded_params = urllib.parse.urlencode(query_params)
        res = self.client.get(self.base_url + '?' + encoded_params)

        if res.status_code != 200 and res.status_code != 204:
            logging.error('client could not load shape. stopping all users')
            self.environment.runner.quit()
            return

        query_params['offset'] = res.headers['x-electric-chunk-last-offset']
        query_params['shape_id'] = res.headers['x-electric-shape-id']
        query_params['live'] = 'true'
        query_params['where'] = get_shape_where(self.shape_size, self.num_shapes)

        self.query_params = query_params

    @task
    def live_mode(self):
        query_params = self.query_params

        encoded_params = urllib.parse.urlencode(query_params)
        res = self.client.get(self.base_url + '?' + encoded_params)

        if res.status_code != 200 and res.status_code != 204:
            logging.error('request failed')
            return


def get_shape_where(shape_size, num_shapes):
    base_id = '00000000-0000-0000-0000-000000000000'

    id_range = shape_size * num_shapes
    num_digits = len(str(id_range))

    # generate random number within num_shapes range
    shape_idx = random.randint(0, num_shapes)    

    # fixed size string with leading zeros
    lower = str(shape_idx * shape_size).zfill(num_digits)
    upper = str((shape_idx + 1) * shape_size).zfill(num_digits)

    lower_id = base_id[:-num_digits] + lower
    upper_id = base_id[:-num_digits] + upper

    return 'id>=\'{0}\' and id<\'{1}\''.format(lower_id, upper_id)