# API Workbench

A real HTTP request client for testing services running on your own machine while you work in Codetist.

## What it does

- Sends one request at a time to an HTTP or HTTPS service on `localhost`, `127.0.0.1`, or `::1`.
- Identifies the extension as **API Workbench** in Codetist using `plugin.json` and `codetist-extension.json`, with the root `icon.png` artwork.
- Supports GET, HEAD, POST, PUT, PATCH, DELETE, and OPTIONS.
- Lets you edit request headers and a text request body.
- Displays the actual response status, headers, duration, and body. JSON responses are formatted for reading.
- Runs through Codetist's desktop host so browser CORS restrictions do not block local development APIs.

## Safety and limits

- Requests are manually sent when you press **Send**; there is no scanning, collection runner, or background traffic.
- The host validates the destination and does not follow redirects, so requests cannot be redirected to non-local hosts.
- Request bodies are limited to 256 KB, response bodies to 2 MB, and requests time out after 20 seconds.
- Request data is not saved by the extension. Avoid putting secrets in shared screenshots or copied responses.
- This first release is intentionally for local development APIs. Remote hosts, database connections, and code execution are not supported.

## Use

Start your local API server, open **API** from the extension shortcut, set its URL (for example `http://localhost:3000/health`), choose a method, optionally edit headers/body, then press **Send**.
