import logging
import random
import urllib.parse

from locust import HttpUser, task, constant_pacing


class ElectricClient(HttpUser):
    wait_time = constant_pacing(1)

    shape_name = "issue"
    base_url = "/v1/shape/"+shape_name


    @task
    def sync(self):
        shape_size = ElectricClient.shape_size
        num_rows = ElectricClient.num_rows

        query_params = {
            'offset': '-1',
            'where': get_shape(shape_size, num_rows)
        }

        encoded_params = urllib.parse.urlencode(query_params)
        res = self.client.get(self.base_url + '?' + encoded_params)

        if res.status_code != 200 and res.status_code != 204:
            logging.error('client could not load shape', query_params['where'])
            #self.environment.runner.quit()

def get_shape(shape_size, num_rows):
    base_id = '00000000-0000-0000-0000-000000000000'

    num_digits = len(str(num_rows))

    # generate random number within num_shapes range
    shape_start_id = random.randint(0, num_rows - shape_size)

    # fixed size string with leading zeros
    lower = str(shape_start_id).zfill(num_digits)
    upper = str((shape_start_id + shape_size)).zfill(num_digits)

    lower_id = base_id[:-num_digits] + lower
    upper_id = base_id[:-num_digits] + upper

    return 'id>=\'{0}\' and id<=\'{1}\''.format(lower_id, upper_id)
