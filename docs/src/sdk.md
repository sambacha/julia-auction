# SDK Documentation

## Overview

The Julia Auction System provides official SDKs for multiple programming languages to simplify integration with the auction platform.

## Available SDKs

| Language | Package | Version | Repository |
|----------|---------|---------|------------|
| Julia | `AuctionClient.jl` | 1.0.0 | [GitHub](https://github.com/julia-auction/julia-client) |
| Python | `julia-auction` | 1.0.0 | [PyPI](https://pypi.org/project/julia-auction) |
| TypeScript/JavaScript | `@julia-auction/client` | 1.0.0 | [npm](https://www.npmjs.com/package/@julia-auction/client) |
| Go | `github.com/julia-auction/go-client` | 1.0.0 | [GitHub](https://github.com/julia-auction/go-client) |
| Rust | `julia-auction` | 1.0.0 | [crates.io](https://crates.io/crates/julia-auction) |

## Julia SDK

### Installation

```julia
using Pkg
Pkg.add("AuctionClient")
```

### Quick Start

```julia
using AuctionClient

# Initialize client
client = Client(
    base_url = "https://api.auction.example.com/v1",
    api_key = "your-api-key"
)

# Create an auction
auction = create_auction(client,
    type = :uniform_price,
    reserve_price = 10.0,
    supply_schedule = ElasticSupply(
        base_quantity = 1000.0,
        price_floor = 10.0,
        price_ceiling = 100.0,
        elasticity_type = :exponential
    ),
    duration_ms = 60000
)

# Submit a bid
bid = submit_bid(client, auction.id,
    quantity = 100.0,
    price = 50.0
)

# Get auction results
result = get_auction_result(client, auction.id)
println("Clearing price: $(result.clearing_price)")
```

### Advanced Usage

```julia
using AuctionClient
using Dates

# Configure client with options
client = Client(
    base_url = "https://api.auction.example.com/v1",
    api_key = "your-api-key",
    timeout = 30,
    retry_count = 3,
    retry_delay = 1.0
)

# Batch operations
function run_batch_auction(client::Client, bids::Vector{BidRequest})
    # Create auction
    auction = create_auction(client,
        type = :augmented_uniform,
        reserve_price = 15.0,
        tie_breaking = TieBreaking(0.7, 0.3)
    )
    
    # Submit bids concurrently
    tasks = [Threads.@spawn submit_bid(client, auction.id, bid) for bid in bids]
    submitted_bids = fetch.(tasks)
    
    # Wait for auction completion
    while true
        status = get_auction_status(client, auction.id)
        if status == :completed
            break
        end
        sleep(1)
    end
    
    # Get results
    return get_auction_result(client, auction.id)
end

# WebSocket streaming
function stream_auction(client::Client, auction_id::String)
    websocket_connect(client) do ws
        subscribe(ws, :auction, auction_id)
        
        for message in ws
            if message.type == :auction_update
                println("Current price: $(message.payload.current_price)")
            elseif message.type == :auction_complete
                println("Final clearing price: $(message.payload.clearing_price)")
                break
            end
        end
    end
end

# Error handling
try
    result = create_auction(client, type = :invalid_type)
catch e
    if isa(e, AuctionError)
        println("Auction error: $(e.message)")
        println("Error code: $(e.code)")
    else
        rethrow(e)
    end
end
```

### API Reference

#### Client

```julia
Client(; base_url::String, api_key::String, kwargs...)
```

Parameters:
- `base_url`: API endpoint URL
- `api_key`: Authentication key
- `timeout`: Request timeout in seconds (default: 30)
- `retry_count`: Number of retries (default: 3)
- `retry_delay`: Delay between retries (default: 1.0)

#### Auction Operations

```julia
# Create auction
create_auction(client::Client; type::Symbol, kwargs...)

# Get auction details
get_auction(client::Client, auction_id::String)

# List auctions
list_auctions(client::Client; status::Symbol=nothing, limit::Int=10)

# Get auction result
get_auction_result(client::Client, auction_id::String)
```

#### Bidding Operations

```julia
# Submit bid
submit_bid(client::Client, auction_id::String; 
          quantity::Float64, price::Float64, kwargs...)

# Cancel bid
cancel_bid(client::Client, bid_id::String)

# Get bid status
get_bid_status(client::Client, bid_id::String)

# List bids
list_bids(client::Client, auction_id::String)
```

## Python SDK

### Installation

```bash
pip install julia-auction
```

### Quick Start

```python
from julia_auction import Client, AuctionType, ElasticSupply

# Initialize client
client = Client(
    base_url="https://api.auction.example.com/v1",
    api_key="your-api-key"
)

# Create an auction
auction = client.create_auction(
    auction_type=AuctionType.UNIFORM_PRICE,
    reserve_price=10.0,
    supply_schedule=ElasticSupply(
        base_quantity=1000.0,
        price_floor=10.0,
        price_ceiling=100.0,
        elasticity_type="exponential"
    ),
    duration_ms=60000
)

# Submit a bid
bid = client.submit_bid(
    auction_id=auction.id,
    quantity=100.0,
    price=50.0
)

# Get results
result = client.get_auction_result(auction.id)
print(f"Clearing price: {result.clearing_price}")
```

### Async Support

```python
import asyncio
from julia_auction import AsyncClient

async def run_auction():
    async with AsyncClient(
        base_url="https://api.auction.example.com/v1",
        api_key="your-api-key"
    ) as client:
        # Create auction
        auction = await client.create_auction(
            auction_type=AuctionType.AUGMENTED_UNIFORM,
            reserve_price=15.0
        )
        
        # Submit multiple bids concurrently
        bids = [
            client.submit_bid(auction.id, quantity=100, price=50),
            client.submit_bid(auction.id, quantity=150, price=48),
            client.submit_bid(auction.id, quantity=200, price=45)
        ]
        submitted = await asyncio.gather(*bids)
        
        # Wait for completion
        result = await client.wait_for_completion(auction.id)
        return result

# Run async function
result = asyncio.run(run_auction())
```

### WebSocket Streaming

```python
from julia_auction import WebSocketClient

def on_auction_update(payload):
    print(f"Price update: {payload['current_price']}")

def on_new_bid(payload):
    print(f"New bid: {payload['quantity']} @ {payload['price']}")

# Create WebSocket client
ws_client = WebSocketClient(
    url="wss://api.auction.example.com/v1/ws",
    api_key="your-api-key"
)

# Register handlers
ws_client.on("auction_update", on_auction_update)
ws_client.on("new_bid", on_new_bid)

# Subscribe and run
ws_client.subscribe("auction", auction_id="your-auction-id")
ws_client.run()
```

## TypeScript/JavaScript SDK

### Installation

```bash
npm install @julia-auction/client
# or
yarn add @julia-auction/client
```

### Quick Start

```typescript
import { Client, AuctionType, ElasticSupply } from '@julia-auction/client';

// Initialize client
const client = new Client({
    baseUrl: 'https://api.auction.example.com/v1',
    apiKey: 'your-api-key'
});

// Create an auction
const auction = await client.createAuction({
    type: AuctionType.UniformPrice,
    reservePrice: 10.0,
    supplySchedule: new ElasticSupply({
        baseQuantity: 1000.0,
        priceFloor: 10.0,
        priceCeiling: 100.0,
        elasticityType: 'exponential'
    }),
    durationMs: 60000
});

// Submit a bid
const bid = await client.submitBid(auction.id, {
    quantity: 100.0,
    price: 50.0
});

// Get results
const result = await client.getAuctionResult(auction.id);
console.log(`Clearing price: ${result.clearingPrice}`);
```

### React Hook

```jsx
import { useAuction } from '@julia-auction/react';

function AuctionComponent({ auctionId }) {
    const { auction, bids, submitBid, loading, error } = useAuction(auctionId);
    
    if (loading) return <div>Loading...</div>;
    if (error) return <div>Error: {error.message}</div>;
    
    return (
        <div>
            <h2>Auction {auction.id}</h2>
            <p>Current Price: ${auction.currentPrice}</p>
            <p>Time Remaining: {auction.timeRemaining}s</p>
            
            <button onClick={() => submitBid(100, 50)}>
                Submit Bid: 100 @ $50
            </button>
            
            <h3>Recent Bids</h3>
            <ul>
                {bids.map(bid => (
                    <li key={bid.id}>
                        {bid.quantity} @ ${bid.price}
                    </li>
                ))}
            </ul>
        </div>
    );
}
```

### WebSocket Streaming

```typescript
import { WebSocketClient } from '@julia-auction/client';

const ws = new WebSocketClient({
    url: 'wss://api.auction.example.com/v1/ws',
    apiKey: 'your-api-key'
});

// Subscribe to events
ws.on('auctionUpdate', (payload) => {
    console.log(`Price update: ${payload.currentPrice}`);
});

ws.on('newBid', (payload) => {
    console.log(`New bid: ${payload.quantity} @ ${payload.price}`);
});

// Connect and subscribe
await ws.connect();
await ws.subscribe('auction', { auctionId: 'your-auction-id' });
```

## Go SDK

### Installation

```bash
go get github.com/julia-auction/go-client
```

### Quick Start

```go
package main

import (
    "context"
    "fmt"
    "log"
    
    auction "github.com/julia-auction/go-client"
)

func main() {
    // Initialize client
    client := auction.NewClient(
        "https://api.auction.example.com/v1",
        "your-api-key",
    )
    
    ctx := context.Background()
    
    // Create auction
    auctionResp, err := client.CreateAuction(ctx, &auction.CreateAuctionRequest{
        Type:         auction.UniformPrice,
        ReservePrice: 10.0,
        DurationMS:   60000,
    })
    if err != nil {
        log.Fatal(err)
    }
    
    // Submit bid
    bidResp, err := client.SubmitBid(ctx, auctionResp.ID, &auction.BidRequest{
        Quantity: 100.0,
        Price:    50.0,
    })
    if err != nil {
        log.Fatal(err)
    }
    
    // Get results
    result, err := client.GetAuctionResult(ctx, auctionResp.ID)
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Printf("Clearing price: %.2f\n", result.ClearingPrice)
}
```

## Rust SDK

### Installation

```toml
[dependencies]
julia-auction = "1.0"
tokio = { version = "1", features = ["full"] }
```

### Quick Start

```rust
use julia_auction::{Client, AuctionType, ElasticSupply};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize client
    let client = Client::new(
        "https://api.auction.example.com/v1",
        "your-api-key"
    )?;
    
    // Create auction
    let auction = client.create_auction()
        .auction_type(AuctionType::UniformPrice)
        .reserve_price(10.0)
        .duration_ms(60000)
        .send()
        .await?;
    
    // Submit bid
    let bid = client.submit_bid(&auction.id)
        .quantity(100.0)
        .price(50.0)
        .send()
        .await?;
    
    // Get results
    let result = client.get_auction_result(&auction.id).await?;
    println!("Clearing price: {}", result.clearing_price);
    
    Ok(())
}
```

## Common Patterns

### Error Handling

All SDKs provide consistent error handling:

```python
# Python
from julia_auction import AuctionError, RateLimitError

try:
    result = client.create_auction(...)
except RateLimitError as e:
    print(f"Rate limited, retry after {e.retry_after} seconds")
except AuctionError as e:
    print(f"Auction error: {e.code} - {e.message}")
```

```typescript
// TypeScript
try {
    const result = await client.createAuction(...);
} catch (error) {
    if (error instanceof RateLimitError) {
        console.log(`Rate limited, retry after ${error.retryAfter} seconds`);
    } else if (error instanceof AuctionError) {
        console.log(`Auction error: ${error.code} - ${error.message}`);
    }
}
```

### Retry Logic

All SDKs include automatic retry with exponential backoff:

```julia
# Julia
client = Client(
    base_url = "...",
    api_key = "...",
    retry_count = 3,
    retry_delay = 1.0,
    retry_multiplier = 2.0
)
```

### Pagination

```python
# Python - iterate through all auctions
for auction in client.list_auctions_paginated(status="active"):
    print(f"Auction {auction.id}: {auction.current_price}")
```

```typescript
// TypeScript - manual pagination
let offset = 0;
const limit = 100;

while (true) {
    const response = await client.listAuctions({ 
        status: 'active', 
        limit, 
        offset 
    });
    
    for (const auction of response.auctions) {
        console.log(`Auction ${auction.id}: ${auction.currentPrice}`);
    }
    
    if (response.auctions.length < limit) break;
    offset += limit;
}
```

## Testing

### Mock Client

All SDKs provide mock clients for testing:

```python
# Python
from julia_auction.testing import MockClient

def test_auction_flow():
    client = MockClient()
    
    # Configure mock responses
    client.set_response('create_auction', {
        'id': 'test-auction-id',
        'status': 'active'
    })
    
    # Test your code
    auction = client.create_auction(...)
    assert auction.id == 'test-auction-id'
```

```typescript
// TypeScript
import { MockClient } from '@julia-auction/client/testing';

test('auction flow', async () => {
    const client = new MockClient();
    
    // Configure mock responses
    client.setResponse('createAuction', {
        id: 'test-auction-id',
        status: 'active'
    });
    
    // Test your code
    const auction = await client.createAuction(...);
    expect(auction.id).toBe('test-auction-id');
});
```

## Performance Tips

1. **Connection Pooling**: Reuse client instances
2. **Batch Operations**: Use batch endpoints when available
3. **Async/Concurrent**: Submit multiple requests concurrently
4. **WebSocket**: Use WebSocket for real-time updates instead of polling
5. **Caching**: Cache auction metadata locally

## Migration Guide

### From v0.x to v1.0

Key changes:
- Renamed `AuctionClient` to `Client`
- Async methods now default in Python/JS
- WebSocket client separated from main client
- Improved type safety in all languages

```python
# Old (v0.x)
from julia_auction import AuctionClient
client = AuctionClient(...)
auction = client.create_auction_sync(...)

# New (v1.0)
from julia_auction import Client
client = Client(...)
auction = await client.create_auction(...)
```

## Support

- **Documentation**: [Full API Reference](api_reference.md)
- **Examples**: [Code Examples](examples.md)
- **Issues**: Report SDK issues on respective GitHub repos
- **Discord**: [Join our Discord](https://discord.gg/julia-auction)

## License

All SDKs are released under the MIT License.