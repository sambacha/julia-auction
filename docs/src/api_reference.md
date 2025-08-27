# API Reference

## Base URL

```
Production: https://api.auction.example.com/v1
Staging: https://staging.auction.example.com/v1
Development: http://localhost:8080/v1
```

## Authentication

All API requests must authenticate with Bearer tokens:

```http
Authorization: Bearer <token>
```

## Common Headers

```http
Content-Type: application/json
X-Correlation-ID: <uuid>
X-Request-ID: <uuid>
```

## Endpoints

### Auctions

#### Create Auction

```http
POST /auctions
```

**Request Body:**
```json
{
  "type": "uniform_price",
  "reserve_price": 10.0,
  "supply_schedule": {
    "base_quantity": 1000.0,
    "price_floor": 10.0,
    "price_ceiling": 100.0,
    "elasticity_type": "exponential",
    "elasticity_factor": 1.5
  },
  "duration_ms": 60000,
  "allow_partial_fills": true
}
```

**Response:**
```json
{
  "auction_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "active",
  "created_at": "2024-01-01T00:00:00Z",
  "ends_at": "2024-01-01T00:01:00Z"
}
```

#### Get Auction Details

```http
GET /auctions/{auction_id}
```

**Response:**
```json
{
  "auction_id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "uniform_price",
  "status": "active",
  "reserve_price": 10.0,
  "current_price": 45.0,
  "total_bids": 42,
  "total_quantity": 5000.0,
  "created_at": "2024-01-01T00:00:00Z",
  "ends_at": "2024-01-01T00:01:00Z"
}
```

#### List Active Auctions

```http
GET /auctions?status=active&limit=10&offset=0
```

**Query Parameters:**
- `status` (optional): Filters by status (active, completed, cancelled)
- `type` (optional): Filters by auction type
- `limit` (optional): Limits results (default: 10, max: 100)
- `offset` (optional): Sets pagination offset (default: 0)

**Response:**
```json
{
  "auctions": [
    {
      "auction_id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "uniform_price",
      "status": "active",
      "current_price": 45.0,
      "ends_at": "2024-01-01T00:01:00Z"
    }
  ],
  "total": 42,
  "limit": 10,
  "offset": 0
}
```

### Bidding

#### Submit Bid

```http
POST /auctions/{auction_id}/bids
```

**Request Body:**
```json
{
  "quantity": 100.0,
  "price": 50.0,
  "is_marginal": false,
  "metadata": {
    "strategy": "aggressive",
    "source": "api"
  }
}
```

**Response:**
```json
{
  "bid_id": "660e8400-e29b-41d4-a716-446655440001",
  "auction_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending",
  "quantity": 100.0,
  "price": 50.0,
  "timestamp": "2024-01-01T00:00:30Z"
}
```

#### Cancel Bid

```http
DELETE /bids/{bid_id}
```

**Response:**
```json
{
  "bid_id": "660e8400-e29b-41d4-a716-446655440001",
  "status": "cancelled",
  "cancelled_at": "2024-01-01T00:00:45Z"
}
```

#### Get Bid Status

```http
GET /bids/{bid_id}
```

**Response:**
```json
{
  "bid_id": "660e8400-e29b-41d4-a716-446655440001",
  "auction_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "allocated",
  "quantity": 100.0,
  "price": 50.0,
  "allocated_quantity": 100.0,
  "clearing_price": 48.0,
  "timestamp": "2024-01-01T00:00:30Z"
}
```

### Settlement

#### Get Settlement Status

```http
GET /settlements/{auction_id}
```

**Response:**
```json
{
  "auction_id": "550e8400-e29b-41d4-a716-446655440000",
  "settlement_id": "770e8400-e29b-41d4-a716-446655440002",
  "status": "completed",
  "clearing_price": 48.0,
  "total_allocated": 4500.0,
  "total_revenue": 216000.0,
  "phantom_improvement_bps": 25,
  "execution_details": {
    "cfmm_routes": [
      {
        "path": ["USDC", "ETH", "DAI"],
        "pools": ["UniswapV3_USDC_ETH", "UniswapV3_ETH_DAI"],
        "amounts": [10000.0, 3.5, 10500.0]
      }
    ],
    "gas_used": 250000,
    "slippage": 0.015
  },
  "settled_at": "2024-01-01T00:01:15Z"
}
```

#### Trigger Manual Settlement

```http
POST /settlements/{auction_id}/execute
```

**Request Body:**
```json
{
  "force": false,
  "max_slippage": 0.02
}
```

**Response:**
```json
{
  "settlement_id": "770e8400-e29b-41d4-a716-446655440002",
  "status": "processing",
  "estimated_completion": "2024-01-01T00:01:20Z"
}
```

### Phantom Auctions

#### Get Phantom Auction Results

```http
GET /phantom-auctions/{auction_id}
```

**Response:**
```json
{
  "auction_id": "550e8400-e29b-41d4-a716-446655440000",
  "phantom_auction_id": "880e8400-e29b-41d4-a716-446655440003",
  "mechanism": "vickrey",
  "phantom_bids_count": 15,
  "real_bids_count": 42,
  "price_discovery": {
    "initial_price": 45.0,
    "discovered_price": 48.0,
    "improvement_bps": 25
  },
  "efficiency_score": 0.94,
  "completed_at": "2024-01-01T00:01:05Z"
}
```

### Market Data

#### Get Order Book

```http
GET /market-data/order-book/{token_pair}
```

**Response:**
```json
{
  "token_pair": "ETH/USDC",
  "bids": [
    {"price": 2500.0, "quantity": 10.0},
    {"price": 2499.0, "quantity": 15.0}
  ],
  "asks": [
    {"price": 2501.0, "quantity": 8.0},
    {"price": 2502.0, "quantity": 12.0}
  ],
  "spread": 1.0,
  "mid_price": 2500.5,
  "timestamp": "2024-01-01T00:00:00Z"
}
```

#### Get Price Feed

```http
GET /market-data/prices/{token}
```

**Response:**
```json
{
  "token": "ETH",
  "prices": {
    "usd": 2500.0,
    "dai": 2500.5,
    "usdc": 2500.0
  },
  "24h_change": 0.025,
  "timestamp": "2024-01-01T00:00:00Z"
}
```

### Admin Endpoints

#### Circuit Breaker Status

```http
GET /admin/circuit-breaker/status
```

**Response:**
```json
{
  "states": {
    "cfmm_bridge": "closed",
    "settlement": "closed",
    "phantom_auction": "half_open"
  },
  "metrics": {
    "cfmm_bridge": {
      "failure_count": 0,
      "success_rate": 1.0,
      "last_failure": null
    }
  }
}
```

#### Reset Circuit Breaker

```http
POST /admin/circuit-breaker/reset
```

**Request Body:**
```json
{
  "component": "phantom_auction"
}
```

#### Participant Health

```http
GET /admin/participants/health
```

**Response:**
```json
{
  "participants": [
    {
      "id": "990e8400-e29b-41d4-a716-446655440004",
      "address": "192.168.1.10:8080",
      "status": "active",
      "last_heartbeat": "2024-01-01T00:00:55Z",
      "consensus_participation_rate": 0.98
    }
  ],
  "total_active": 3,
  "total_inactive": 0,
  "consensus_health": "healthy"
}
```

### Health & Monitoring

#### Health Check

```http
GET /health/ready
```

**Response:**
```json
{
  "status": "ready",
  "version": "1.0.0",
  "components": {
    "database": "healthy",
    "redis": "healthy",
    "cfmm_bridge": "healthy"
  }
}
```

#### Liveness Check

```http
GET /health/live
```

**Response:**
```json
{
  "status": "alive",
  "uptime_seconds": 3600
}
```

#### Metrics

```http
GET /metrics
```

**Response (Prometheus format):**
```
# HELP auction_requests_total Total number of auction requests
# TYPE auction_requests_total counter
auction_requests_total{method="POST",endpoint="/auctions"} 42

# HELP auction_latency_seconds Auction processing latency
# TYPE auction_latency_seconds histogram
auction_latency_seconds_bucket{le="0.001"} 10
auction_latency_seconds_bucket{le="0.005"} 35
auction_latency_seconds_bucket{le="0.01"} 40
auction_latency_seconds_sum 0.25
auction_latency_seconds_count 42
```

## WebSocket API

### Connection

```javascript
const ws = new WebSocket('wss://api.auction.example.com/v1/ws');

ws.onopen = () => {
  // Authenticate
  ws.send(JSON.stringify({
    type: 'auth',
    token: 'Bearer <token>'
  }));
};
```

### Subscribe to Auction Updates

```javascript
// Subscribe
ws.send(JSON.stringify({
  type: 'subscribe',
  channel: 'auction',
  auction_id: '550e8400-e29b-41d4-a716-446655440000'
}));

// Receive updates
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === 'auction_update') {
    console.log('Auction update:', data.payload);
  }
};
```

### Real-time Bid Stream

```javascript
// Subscribe to bid stream
ws.send(JSON.stringify({
  type: 'subscribe',
  channel: 'bids',
  auction_id: '550e8400-e29b-41d4-a716-446655440000'
}));

// Receive bid updates
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === 'new_bid') {
    console.log('New bid:', data.payload);
  }
};
```

## Error Responses

### Error Format

```json
{
  "error": {
    "code": "AUCTION_NOT_FOUND",
    "message": "Auction with ID 550e8400-e29b-41d4-a716-446655440000 not found",
    "details": {
      "auction_id": "550e8400-e29b-41d4-a716-446655440000"
    },
    "correlation_id": "aa0e8400-e29b-41d4-a716-446655440005"
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `UNAUTHORIZED` | 401 | Invalid or missing authentication |
| `FORBIDDEN` | 403 | Insufficient permissions |
| `AUCTION_NOT_FOUND` | 404 | Auction does not exist |
| `BID_TOO_LOW` | 400 | Bid below reserve price |
| `AUCTION_ENDED` | 400 | Auction has already ended |
| `INSUFFICIENT_LIQUIDITY` | 400 | Not enough liquidity for settlement |
| `CIRCUIT_BREAKER_OPEN` | 503 | Service temporarily unavailable |
| `RATE_LIMITED` | 429 | Too many requests |

## Rate Limiting

We enforce rate limits per API key:

| Endpoint | Limit |
|----------|-------|
| Create Auction | 10/minute |
| Submit Bid | 100/minute |
| Get Auction | 1000/minute |
| WebSocket Connections | 10 concurrent |

Rate limit headers include:
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1704067260
```

## SDK Examples

### Julia Client

```julia
using HTTP
using JSON

struct AuctionClient
    base_url::String
    token::String
end

function create_auction(client::AuctionClient, params::Dict)
    response = HTTP.post(
        "$(client.base_url)/auctions",
        ["Authorization" => "Bearer $(client.token)",
         "Content-Type" => "application/json"],
        JSON.json(params)
    )
    return JSON.parse(String(response.body))
end

# Usage
client = AuctionClient("https://api.auction.example.com/v1", "your-token")
auction = create_auction(client, Dict(
    "type" => "uniform_price",
    "reserve_price" => 10.0
))
```

### Python Client

```python
import requests

class AuctionClient:
    def __init__(self, base_url, token):
        self.base_url = base_url
        self.headers = {
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json'
        }
    
    def create_auction(self, params):
        response = requests.post(
            f'{self.base_url}/auctions',
            headers=self.headers,
            json=params
        )
        return response.json()
    
    def submit_bid(self, auction_id, quantity, price):
        response = requests.post(
            f'{self.base_url}/auctions/{auction_id}/bids',
            headers=self.headers,
            json={'quantity': quantity, 'price': price}
        )
        return response.json()

# Usage
client = AuctionClient('https://api.auction.example.com/v1', 'your-token')
auction = client.create_auction({
    'type': 'uniform_price',
    'reserve_price': 10.0
})
```

## Next Steps

- [WebSocket Guide](websocket.md) - Real-time communication
- [SDK Documentation](sdk.md) - Client library reference
- [Examples](examples.md) - Code examples and tutorials