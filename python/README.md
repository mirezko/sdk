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

## Evaluating automated campaigns

```python
client.evaluate(['campaign1', 'campaign2'])
```

will return

```python
{
  'campaign1': {'success': True, 'errors': []},
  'campaign2': {'success': True, 'errors': []}
}
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

# Evaluate automated campaign
./seven_segments.py evaluate "$COMPANY_TOKEN" "$CUSTOMER" campaign1 campaign2
```
