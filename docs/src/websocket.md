# WebSocket API Guide

## Overview

The Julia Auction System provides real-time WebSocket communication for live auction updates, bid streaming, and settlement notifications.

## Connection Setup

### Establishing Connection

```javascript
const ws = new WebSocket('wss://api.auction.example.com/v1/ws');

ws.onopen = () => {
    console.log('WebSocket connection established');
    // Authenticate immediately after connection
    ws.send(JSON.stringify({
        type: 'auth',
        token: 'Bearer YOUR_TOKEN_HERE'
    }));
};

ws.onerror = (error) => {
    console.error('WebSocket error:', error);
};

ws.onclose = (event) => {
    console.log(`Connection closed: ${event.code} - ${event.reason}`);
    // Implement reconnection logic here
};
```

### Authentication

All WebSocket connections require authentication within 5 seconds of connection:

```javascript
// Authentication message
{
    "type": "auth",
    "token": "Bearer eyJhbGciOiJIUzI1NiIs..."
}

// Success response
{
    "type": "auth_success",
    "client_id": "550e8400-e29b-41d4-a716-446655440000",
    "permissions": ["read", "write", "subscribe"]
}

// Failure response
{
    "type": "auth_failure",
    "error": "Invalid token"
}
```

## Channel Subscriptions

### Available Channels

| Channel | Description | Message Types |
|---------|-------------|---------------|
| `auction` | Auction state updates | `auction_update`, `auction_complete` |
| `bids` | Live bid stream | `new_bid`, `bid_accepted`, `bid_rejected` |
| `settlement` | Settlement updates | `settlement_started`, `settlement_complete` |
| `market_data` | Price feed updates | `price_update`, `order_book_update` |

### Subscription Examples

#### Auction Updates

```javascript
// Subscribe to auction updates
ws.send(JSON.stringify({
    type: 'subscribe',
    channel: 'auction',
    auction_id: '550e8400-e29b-41d4-a716-446655440000'
}));

// Receive auction updates
ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    
    switch(data.type) {
        case 'auction_update':
            console.log('Current price:', data.payload.current_price);
            console.log('Total bids:', data.payload.total_bids);
            break;
            
        case 'auction_complete':
            console.log('Clearing price:', data.payload.clearing_price);
            console.log('Total allocated:', data.payload.total_allocated);
            break;
    }
};
```

#### Bid Stream

```javascript
// Subscribe to all bids for an auction
ws.send(JSON.stringify({
    type: 'subscribe',
    channel: 'bids',
    auction_id: '550e8400-e29b-41d4-a716-446655440000',
    options: {
        include_own: true,  // Include your own bids
        min_quantity: 100   // Only bids >= 100
    }
}));

// Handle bid messages
ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    
    if (data.type === 'new_bid') {
        const bid = data.payload;
        console.log(`New bid: ${bid.quantity} @ ${bid.price}`);
        updateOrderBook(bid);
    }
};
```

#### Settlement Notifications

```javascript
// Subscribe to settlement updates
ws.send(JSON.stringify({
    type: 'subscribe',
    channel: 'settlement',
    auction_id: '550e8400-e29b-41d4-a716-446655440000'
}));

// Handle settlement messages
ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    
    if (data.type === 'settlement_complete') {
        console.log('Settlement ID:', data.payload.settlement_id);
        console.log('Gas used:', data.payload.gas_used);
        console.log('Execution path:', data.payload.execution_path);
    }
};
```

## Message Protocol

### Message Format

All messages follow this structure:

```typescript
interface WebSocketMessage {
    type: string;           // Message type
    payload?: any;         // Message data
    timestamp: string;     // ISO 8601 timestamp
    sequence: number;      // Message sequence number
    correlation_id?: string; // Optional correlation ID
}
```

### Outgoing Message Types

#### Submit Bid via WebSocket

```javascript
ws.send(JSON.stringify({
    type: 'submit_bid',
    auction_id: '550e8400-e29b-41d4-a716-446655440000',
    payload: {
        quantity: 100.0,
        price: 50.0,
        is_marginal: false
    }
}));
```

#### Cancel Bid

```javascript
ws.send(JSON.stringify({
    type: 'cancel_bid',
    bid_id: '660e8400-e29b-41d4-a716-446655440001'
}));
```

#### Unsubscribe

```javascript
ws.send(JSON.stringify({
    type: 'unsubscribe',
    channel: 'bids',
    auction_id: '550e8400-e29b-41d4-a716-446655440000'
}));
```

### Incoming Message Types

#### Auction State Update

```json
{
    "type": "auction_update",
    "timestamp": "2024-01-01T00:00:30Z",
    "sequence": 42,
    "payload": {
        "auction_id": "550e8400-e29b-41d4-a716-446655440000",
        "status": "active",
        "current_price": 48.5,
        "total_bids": 127,
        "total_quantity": 15000.0,
        "time_remaining_ms": 30000,
        "supply_available": 10000.0
    }
}
```

#### New Bid Notification

```json
{
    "type": "new_bid",
    "timestamp": "2024-01-01T00:00:31Z",
    "sequence": 43,
    "payload": {
        "bid_id": "660e8400-e29b-41d4-a716-446655440001",
        "auction_id": "550e8400-e29b-41d4-a716-446655440000",
        "quantity": 100.0,
        "price": 52.0,
        "timestamp": "2024-01-01T00:00:31Z",
        "is_phantom": false
    }
}
```

#### Settlement Progress

```json
{
    "type": "settlement_progress",
    "timestamp": "2024-01-01T00:01:00Z",
    "sequence": 44,
    "payload": {
        "settlement_id": "770e8400-e29b-41d4-a716-446655440002",
        "phase": "consensus",
        "participants_agreed": 7,
        "participants_total": 10,
        "estimated_completion": "2024-01-01T00:01:15Z"
    }
}
```

## Connection Management

### Heartbeat/Ping-Pong

The server sends ping messages every 30 seconds:

```javascript
// Handle ping-pong
ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    
    if (data.type === 'ping') {
        ws.send(JSON.stringify({
            type: 'pong',
            timestamp: new Date().toISOString()
        }));
    }
};
```

### Reconnection Strategy

```javascript
class WebSocketClient {
    constructor(url, token) {
        this.url = url;
        this.token = token;
        this.reconnectInterval = 1000;
        this.maxReconnectInterval = 30000;
        this.reconnectAttempts = 0;
        this.subscriptions = new Map();
        
        this.connect();
    }
    
    connect() {
        this.ws = new WebSocket(this.url);
        
        this.ws.onopen = () => {
            console.log('Connected');
            this.reconnectAttempts = 0;
            this.reconnectInterval = 1000;
            
            // Authenticate
            this.authenticate();
            
            // Resubscribe to channels
            this.resubscribe();
        };
        
        this.ws.onclose = () => {
            console.log('Disconnected, reconnecting...');
            this.scheduleReconnect();
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
            this.ws.close();
        };
    }
    
    scheduleReconnect() {
        setTimeout(() => {
            this.reconnectAttempts++;
            this.connect();
        }, Math.min(this.reconnectInterval * Math.pow(2, this.reconnectAttempts), 
                   this.maxReconnectInterval));
    }
    
    authenticate() {
        this.send({
            type: 'auth',
            token: `Bearer ${this.token}`
        });
    }
    
    resubscribe() {
        for (const [key, subscription] of this.subscriptions) {
            this.send(subscription);
        }
    }
    
    subscribe(channel, options) {
        const subscription = {
            type: 'subscribe',
            channel: channel,
            ...options
        };
        
        const key = `${channel}:${options.auction_id || 'global'}`;
        this.subscriptions.set(key, subscription);
        
        if (this.ws.readyState === WebSocket.OPEN) {
            this.send(subscription);
        }
    }
    
    send(data) {
        if (this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify(data));
        }
    }
}
```

## Error Handling

### Error Message Format

```json
{
    "type": "error",
    "error": {
        "code": "SUBSCRIPTION_FAILED",
        "message": "Cannot subscribe to completed auction",
        "details": {
            "auction_id": "550e8400-e29b-41d4-a716-446655440000",
            "status": "completed"
        }
    },
    "correlation_id": "aa0e8400-e29b-41d4-a716-446655440005"
}
```

### Common Error Codes

| Code | Description |
|------|-------------|
| `AUTH_REQUIRED` | Authentication required |
| `AUTH_FAILED` | Authentication failed |
| `SUBSCRIPTION_FAILED` | Unable to subscribe to channel |
| `INVALID_MESSAGE` | Malformed message |
| `RATE_LIMITED` | Too many messages |
| `AUCTION_NOT_FOUND` | Auction does not exist |
| `PERMISSION_DENIED` | Insufficient permissions |

## Rate Limiting

WebSocket connections have the following limits:

| Limit Type | Value |
|------------|-------|
| Messages per second | 100 |
| Subscriptions per connection | 50 |
| Total connections per client | 10 |
| Message size | 64KB |

Rate limit exceeded response:
```json
{
    "type": "rate_limit",
    "error": {
        "code": "RATE_LIMITED",
        "message": "Message rate limit exceeded",
        "retry_after": 1000
    }
}
```

## Client Libraries

### Julia WebSocket Client

```julia
using HTTP.WebSockets
using JSON

struct AuctionWebSocket
    url::String
    token::String
    handlers::Dict{String, Function}
end

function connect_websocket(client::AuctionWebSocket)
    WebSockets.open(client.url) do ws
        # Authenticate
        send(ws, JSON.json(Dict(
            "type" => "auth",
            "token" => "Bearer $(client.token)"
        )))
        
        # Message handler
        for msg in ws
            data = JSON.parse(String(msg))
            if haskey(client.handlers, data["type"])
                client.handlers[data["type"]](data["payload"])
            end
        end
    end
end

# Usage
client = AuctionWebSocket(
    "wss://api.auction.example.com/v1/ws",
    "your-token",
    Dict(
        "auction_update" => (payload) -> println("Price: $(payload["current_price"])"),
        "new_bid" => (payload) -> println("New bid: $(payload["quantity"])")
    )
)

connect_websocket(client)
```

### Python WebSocket Client

```python
import asyncio
import websockets
import json

class AuctionWebSocket:
    def __init__(self, url, token):
        self.url = url
        self.token = token
        self.handlers = {}
    
    def on(self, event_type, handler):
        self.handlers[event_type] = handler
        return self
    
    async def connect(self):
        async with websockets.connect(self.url) as websocket:
            # Authenticate
            await websocket.send(json.dumps({
                'type': 'auth',
                'token': f'Bearer {self.token}'
            }))
            
            # Subscribe to channels
            await websocket.send(json.dumps({
                'type': 'subscribe',
                'channel': 'auction',
                'auction_id': 'your-auction-id'
            }))
            
            # Handle messages
            async for message in websocket:
                data = json.loads(message)
                if data['type'] in self.handlers:
                    await self.handlers[data['type']](data.get('payload'))

# Usage
client = AuctionWebSocket('wss://api.auction.example.com/v1/ws', 'your-token')

client.on('auction_update', lambda p: print(f"Price: {p['current_price']}"))
client.on('new_bid', lambda p: print(f"Bid: {p['quantity']} @ {p['price']}"))

asyncio.run(client.connect())
```

## Testing WebSocket Connections

### Using wscat

```bash
# Install wscat
npm install -g wscat

# Connect to WebSocket
wscat -c wss://api.auction.example.com/v1/ws

# Authenticate
{"type":"auth","token":"Bearer YOUR_TOKEN"}

# Subscribe to auction
{"type":"subscribe","channel":"auction","auction_id":"550e8400-e29b-41d4-a716-446655440000"}
```

### Load Testing

```javascript
// WebSocket load test script
const WebSocket = require('ws');

async function loadTest(connections, messagesPerSecond) {
    const clients = [];
    
    // Create connections
    for (let i = 0; i < connections; i++) {
        const ws = new WebSocket('wss://api.auction.example.com/v1/ws');
        
        ws.on('open', () => {
            // Authenticate
            ws.send(JSON.stringify({
                type: 'auth',
                token: 'Bearer test-token'
            }));
            
            // Send messages at specified rate
            setInterval(() => {
                ws.send(JSON.stringify({
                    type: 'ping',
                    timestamp: new Date().toISOString()
                }));
            }, 1000 / messagesPerSecond);
        });
        
        clients.push(ws);
    }
    
    // Monitor for 60 seconds
    await new Promise(resolve => setTimeout(resolve, 60000));
    
    // Close all connections
    clients.forEach(ws => ws.close());
}

// Run load test: 100 connections, 10 messages/sec each
loadTest(100, 10);
```

## Next Steps

- [API Reference](api_reference.md) - REST API documentation
- [SDK Documentation](sdk.md) - Client libraries
- [Examples](examples.md) - Code examples