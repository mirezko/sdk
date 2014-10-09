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


DEFAULT_TARGET = 'https://api.7segments.com'
DEFAULT_LOGGER = logging.getLogger(__name__)


class InvalidRequest(Exception):
    pass


class ServiceUnavailable(Exception):
    pass


class _SevenSegmentsBase(object):

    def __init__(self, target=None):
        self._target = DEFAULT_TARGET if target is None else target

    def _url(self, url):
        return '{}{}'.format(self._target, url)


class AuthenticatedSevenSegments(_SevenSegmentsBase):

    def __init__(self, username, password, target=None):
        super(AuthenticatedSevenSegments, self).__init__(target)
        self._session = requests.Session()
        self._session.auth = (username, password)

    def export_analysis(self, analysis_type, data, token=None):
        params = {} if token is None else {'company': token}
        response = self._session.post(
            self._url('/analytics/{}'.format(analysis_type)),
            data=json.dumps(data),
            params=params,
            headers={'Content-type': 'application/json'}
        )
        return _handle_response(response)


class SevenSegments(_SevenSegmentsBase):

    def __init__(self, token, customer=None, target=None, silent=True, logger=None):
        super(SevenSegments, self).__init__(target)
        self._token = token
        self._customer = self._convert_customer_argument(customer)
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

    def get_html(self, html_campaign_name):
        response = self._post('/campaigns/html/get', {
            'customer_ids': self._customer,
            'company_id': self._token,
            'html_campaign_name': html_campaign_name
        })
        return _handle_response(response)['data']

    @staticmethod
    def _convert_customer_argument(customer):
        if customer is None:
            return {}
        elif isinstance(customer, basestring):
            return {'registered': customer}
        elif isinstance(customer, dict):
            return customer
        raise ValueError('Attribute customer should be None, string or dict')

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
                self._logger.exception('Failed connecting to 7SEGMENTS API')


def _handle_response(response):
    if response.status_code == 401:
        raise InvalidRequest({'message': response.text, 'code': 401})

    json_response = response.json()

    if json_response['success']:
        return json_response

    if response.status_code == 500:
        raise ServiceUnavailable()

    raise InvalidRequest(json_response['errors'])


def _add_common_arguments(parser):
    parser.add_argument('token')
    parser.add_argument('registered_customer_id')
    parser.add_argument('--target', default=DEFAULT_TARGET, metavar='URL')


if __name__ == '__main__':
    from argparse import ArgumentParser

    parser = ArgumentParser()
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

    def get_html():
        print(client.get_html(args.html_campaign_name))

    parser_track = commands.add_parser('track', help='Track event')
    _add_common_arguments(parser_track)
    parser_track.add_argument('event_type')
    parser_track.add_argument('--properties', nargs='+', help='key=value', type=property, default=[])
    parser_track.set_defaults(func=track)

    parser_update = commands.add_parser('update', help='Update customer properties')
    _add_common_arguments(parser_update)
    parser_update.add_argument('properties', nargs='+', help='key=value', type=property, default=[])
    parser_update.set_defaults(func=update)

    parser_get_html = commands.add_parser('get_html', help='Get HTML from campaign')
    _add_common_arguments(parser_get_html)
    parser_get_html.add_argument('html_campaign_name')
    parser_get_html.set_defaults(func=get_html)

    args = parser.parse_args()

    client = SevenSegments(args.token, customer=args.registered_customer_id, target=args.target, silent=False)
    args.func()