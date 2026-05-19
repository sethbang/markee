# Pancake HTTP API

Version 2 of the Pancake API. Every request is JSON over HTTPS, and every
response carries a `request-id` header so you can trace it in the logs.

## Authentication

Pass your key as a bearer token on each request:

```sh
curl https://api.pancake.dev/v2/notes \
  -H "Authorization: Bearer $PANCAKE_KEY" \
  -H "Accept: application/json"
```

## List notes

```http
GET /v2/notes?limit=20&cursor=eyJpZCI6OTB9
```

Returns a page of notes, newest first, with an opaque cursor for the next
page:

```json
{
  "data": [
    { "id": "n_8f2a", "title": "Roadmap", "updated": 1716100000 },
    { "id": "n_8f29", "title": "Sprint 14", "updated": 1716090000 }
  ],
  "next_cursor": "eyJpZCI6IDg5fQ"
}
```

## Create a note

```json
POST /v2/notes
{
  "title": "Sprint 15",
  "body": "## Goals\n- Ship search\n- Cut render time"
}
```

## Errors

A failed request returns a typed error object and an appropriate status code:

```json
{ "error": { "code": "rate_limited", "retry_after": 30 } }
```
