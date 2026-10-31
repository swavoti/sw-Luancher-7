# Changelog

## 1.0.0

- Add a working localhost-only HTTP client with manual request sending.
- Show real response status, headers, duration, and body.
- Route requests through the desktop host to support local APIs without browser CORS failures.
- Enforce loopback-only destinations, no automatic redirects, and request/response size limits.
