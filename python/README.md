# 7SEGMENTS python API client

The `seven_segments.SevenSegments` class provides access to the 7SEGMENTS
synchronous python tracking API. In order to track events, instantiate the
class at least with your company token (you can get it when you log in to 7SEGMENTS), for example:

```python
from seven_segments import SevenSegments

client = SevenSegments('12345678-90ab-cdef-1234-567890abcdef')
```

## Identifying the customer

When tracking events, you have to specify which customer generated
them. This can be either done right when calling the client's
constructor.

```python
client = SevenSegments('12345678-90ab-cdef-1234-567890abcdef', customer='john123')
```

or by calling `identify`.

```python
client.identify('john123')
```

## Tracking events

To track events for the currently selected customer, simply
call the `track` method.

```python
client.track('purchase')
```

You can also specify a dictionary of event properties to store
with the event.

```python
client.track('purchase', properties={'product': 'bottle', 'amount': 5})
```

## Updating customer properties

You can also update information that is stored with a customer.

```python
client.update({'first_name': 'John', 'last_name': 'Smith'})
```

## Getting HTML from campaign

```python
client.get_html('Banner left')
```

will return

```python
'<img src="/my-awesome-banner-1.png" />'
```

## Using on the command line

The python client also has a command-line interface that allows to call its essential functions.

```bash
COMPANY_TOKEN='12345678-90ab-cdef-1234-567890abcdef'
CUSTOMER='john123'

# Track event
./seven_segments.py track "$COMPANY_TOKEN" "$CUSTOMER" purchase --properties product=bottle amount=5

# Update customer properties
./seven_segments.py update "$COMPANY_TOKEN" "$CUSTOMER" first_name=John last_name=Smith

# Get HTML from campaign
./seven_segments.py get_html "$COMPANY_TOKEN" "$CUSTOMER" banner
```

# 7SEGMENTS python Authenticated API client

The `seven_segments.AuthenticatedSevenSegments` class provides access to the 7SEGMENTS
synchronous python authenticated API. In order to export analyses you have to instantiate client
with username and password of user that has ExtAPI access:

```python
from seven_segments import SevenSegments

client = AuthenticatedSevenSegments('username', 'password')
```

## Exporting analyses

First argument is type of analysis (funnel, report, retention, segmentation), second argument is JSON in format documented at https://docs.7segments.com/technical-guide/export-api/
In case that authenticated customer has access to multiple companies use keyword argument token=token_of_company_with_given_analysis

```python
client.export_analysis('funnel', {
    'analysis_id': '2f86608f-24f5-11e3-9950-c48508494cf5'
})
```

will return

```python
{
    "success": true,
    "name": "Conversion funnel",
    "steps": ["First visit", "Registration", "First log in", "Purchase", "Payment"],
    "total": {
        "counts": [48632, 24120, 20398, 1256, 1250],
        "times": [-1, 680, 4502, 45, 540, 300],
        "metric": 1987562
    },
    "drill_down": {
        "type": "none",
        "series": []
    },
    "metric": {
        "step": 4,
        "property": "price"
    }
}
```