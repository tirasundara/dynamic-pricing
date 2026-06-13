# 🏨 Tripla Dynamic Pricing Model API

This Docker container runs a simulation of the "computationally expensive" dynamic pricing model mentioned in the take-home assignment. Your proxy service will act as a client to this API to fetch the dynamic room rates.

## How to Run

To start the service, run the following Docker command. The API will be available on `http://localhost:8080`.

```
docker run -p 8080:8080 tripladev/rate-api
```

## API Documentation

The API exposes a single endpoint for fetching room rates in batches.

### Endpoint Details

- Method: `POST`
- Endpoint: `/pricing`
- Headers: `Content-Type: application/json`, `token: <your_token>`

### Authentication & Usage Limits

This API has a hard-coded authentication token and a strict rate limit to simulate the constraints of a real-world, costly service.
- Token: Only requests with the following `token` in the token header will be accepted. `04aa6f42aa03f220c2ae9a276cd68c62`
- Rate Limit: The `/pricing` endpoint is limited to 1,000 requests per day. During development, you can reset this quota by restarting the Docker container.

### Request Format

The API accepts a JSON object containing an `attributes` array. Each object in the array represents a unique room for which you want to retrieve a price.

```json
{
  "attributes": [
    {
      "period": "Summer",
      "hotel": "FloatingPointResort",
      "room": "SingletonRoom"
    },
    {
      "period": "Autumn",
      "hotel": "FloatingPointResort",
      "room": "SingletonRoom"
    },
    {
      "period": "Winter",
      "hotel": "FloatingPointResort",
      "room": "SingletonRoom"
    },
    {
      "period": "Spring",
      "hotel": "FloatingPointResort",
      "room": "SingletonRoom"
    }
  ]
}
```

### Response Format

The API returns a JSON object containing a `rates` array, with each object corresponding to a room in the request, now including its calculated `rate`.

```json
{
  "rates": [
    {
      "period": "Summer",
      "hotel": "FloatingPointResort",
      "room": "SingletonRoom",
      "rate": "12000"
    },
    {
      "period": "Autumn",
      "hotel": "FloatingPointResort",
      "room": "SingletonRoom",
      "rate": "28000"
    },
    {
      "period": "Winter",
      "hotel": "FloatingPointResort",
      "room": "SingletonRoom",
      "rate": "46000"
    },
    {
      "period": "Spring",
      "hotel": "FloatingPointResort",
      "room": "SingletonRoom",
      "rate": "73000"
    }
  ]
}
```

### Supported Attribute Values

- `period`: `Summer`, `Autumn`, `Winter`, `Spring`
- `hotel`: `FloatingPointResort`, `GitawayHotel`, `RecursionRetreat`
- `room`: `SingletonRoom`, `BooleanTwin`, `RestfulKing`

### Example Request

Here is an example `curl` command to test the running API.

```bash
curl -X POST http://localhost:8080/pricing \
  -H 'token: 04aa6f42aa03f220c2ae9a276cd68c62' \
  -H 'Content-Type: application/json' \
  -d '{
    "attributes": [
      { "period": "Summer", "hotel": "FloatingPointResort", "room": "SingletonRoom" },
      { "period": "Autumn",  "hotel": "GitawayHotel", "room": "RestfulKing" }
    ]
  }'
```

---
_source: https://hub.docker.com/r/tripladev/rate-api_ (last fetched: 2026/06/11)
