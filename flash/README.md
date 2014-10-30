# 7SEGMENTS flash API client

The `com.seven_segments.api.SevenSegments` class provides access to the 7SEGMENTS
asynchronous ActionScript tracking API. In order to track events, instantiate the
class and call initialize with at least the company token (you can get it when you log in to 7SEGMENTS), for example:

```ActionScript
import com.sevensegments.api.SevenSegments;

var _7S:SevenSegments = new SevenSegments();
_7S.initialize({token: '12345678-90ab-cdef-1234-567890abcdef'});
```

## Identifying the customer

When tracking events, you have to specify which customer generated
them. This can be either done right when calling initialize:

```ActionScript
_7S.initialize({token: '12345678-90ab-cdef-1234-567890abcdef', customer: 'john123'});
```

or by calling `identify`.

```ActionScript
_7S.identify('john123');
```

## Tracking events

To track events for the currently selected customer, simply
call the `track` method.

```ActionScript
_7S.track('purchase')
```

You can also specify event properties to store with the event.

```ActionScript
_7S.track('purchase', {'product': 'bottle', 'amount': 5})
```

## Updating customer properties

You can also update information that is stored with a customer.

```ActionScript
_7S.update({'first_name': 'John', 'last_name': 'Smith'})
```

