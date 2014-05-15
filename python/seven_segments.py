#!/usr/bin/env python

# Copyright 2014 7SEGMENTS s.r.o.
# 
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
# 
#        http://www.apache.org/licenses/LICENSE-2.0
# 
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

from __future__ import print_function
import json
import requests
from requests.exceptions import ConnectionError
import logging


DEFAULT_TARGET = 'http://api.7segments.com'
DEFAULT_LOGGER = logging.getLogger(__name__)


class SevenSegments(object):

    def __init__(self, token, customer=None, target=None, silent=True, logger=None):
        self._token = token
        self._customer = self._convert_customer_argument(customer)
        self._target = DEFAULT_TARGET if target is None else target
        self._silent = silent
        self._logger = DEFAULT_LOGGER if logger is None else logger
        self._session = requests.Session()

    def identify(self, customer=None, properties=None):
        self._customer = self._convert_customer_argument(customer)
        self.update({} if properties is None else properties)

    def update(self, properties):
        return self._post('/crm/customers', {
            'ids': self._customer,
            'company_id': self._token,
            'properties': properties
        })

    def track(self, event_type, properties=None):
        return self._post('/crm/events', {
            'customer_ids': self._customer,
            'company_id': self._token,
            'type': event_type,
            'properties': {} if properties is None else properties
        })

    def evaluate(self, campaigns=None, customer_properties=None):
        if campaigns is None:
            campaigns = []
        response = self._post('/campaigns/automated/evaluate', {
            'campaigns': campaigns,
            'ids': self._customer,
            'company_id': self._token,
            'properties': {} if customer_properties is None else customer_properties
        })
        return response.json()['data']

    @staticmethod
    def _convert_customer_argument(customer):
        if customer is None:
            return {}
        elif isinstance(customer, basestring):
            return {'registered': customer}
        elif isinstance(customer, dict):
            return customer
        raise ValueError('Attribute customer should be None, string or dict')

    def _url(self, url):
        return '{}{}'.format(self._target, url)

    def _post(self, url, data):
        try:
            return self._session.post(
                self._url(url),
                data=json.dumps(data),
                headers={'Content-type': 'application/json'}
            )
        except ConnectionError, e:
            if not self._silent:
                raise e
            else:
                self._logger.exception("Failed connecting to 7SEGMENTS API")

if __name__ == '__main__':
    from argparse import ArgumentParser

    parser = ArgumentParser()
    parser.add_argument('token')
    parser.add_argument('registered_customer_id')
    parser.add_argument('--target', default=DEFAULT_TARGET, metavar='URL')

    commands = parser.add_subparsers()

    def property(s):
        prop = s.split('=', 1)
        if len(prop) != 2:
            raise ValueError('Property value not defined')
        return prop

    def track():
        client.track(args.event_type, dict(args.properties))

    def update():
        client.update(dict(args.properties))

    def evaluate():
        response = client.evaluate(args.campaign, dict(args.properties))
        if args.json:
            print(json.dumps(response))
        else:
            for name, campaign in response.iteritems():
                print(name)
                if campaign['success']:
                    print('  Success')
                else:
                    for error in campaign['errors']:
                        print('  ' + error)

    parser_track = commands.add_parser('track', help='Track event')
    parser_track.add_argument('event_type')
    parser_track.add_argument('--properties', nargs='+', help='key=value', type=property, default=[])
    parser_track.set_defaults(func=track)

    parser_update = commands.add_parser('update', help='Update customer properties')
    parser_update.add_argument('properties', nargs='+', help='key=value', type=property, default=[])
    parser_update.set_defaults(func=update)

    parser_evaluate = commands.add_parser('evaluate', help='Evaluate automated campaign')
    parser_evaluate.add_argument('campaign', nargs='+')
    parser_evaluate.add_argument('--properties', nargs='+', help='key=value', type=property, default=[])
    parser_evaluate.add_argument('--json', action='store_true', help='Output JSON')
    parser_evaluate.set_defaults(func=evaluate)

    args = parser.parse_args()

    client = SevenSegments(args.token, customer=args.registered_customer_id, target=args.target, silent=False)

    args.func()
