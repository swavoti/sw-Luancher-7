import React, { useMemo, useState } from 'react';
import './styles.css';

type HttpMethod = 'GET' | 'HEAD' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'OPTIONS';

interface ApiResponse {
  url: string;
  status: number;
  statusText: string;
  headers: Record<string, string>;
  body: string;
  durationMs: number;
}

const METHODS: HttpMethod[] = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];
const INITIAL_HEADERS = JSON.stringify({ Accept: 'application/json' }, null, 2);

function getCodetistApi() {
  if (typeof window === 'undefined') return null;
  return (window as any).codetist || (window as any).ideAPI || null;
}

function isLocalRequestUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return ['http:', 'https:'].includes(url.protocol)
      && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname.toLowerCase())
      && !url.username
      && !url.password;
  } catch {
    return false;
  }
}

function formatResponseBody(body: string, contentType: string | undefined): string {
  if (!body) return '';
  if (!contentType?.toLowerCase().includes('json')) return body;
  try {
    return JSON.stringify(JSON.parse(body), null, 2);
  } catch {
    return body;
  }
}

function App() {
  const [method, setMethod] = useState<HttpMethod>('GET');
  const [url, setUrl] = useState('http://localhost:3000/');
  const [headersText, setHeadersText] = useState(INITIAL_HEADERS);
  const [body, setBody] = useState('');
  const [response, setResponse] = useState<ApiResponse | null>(null);
  const [error, setError] = useState('');
  const [sending, setSending] = useState(false);
  const [copied, setCopied] = useState(false);

  const localUrl = useMemo(() => isLocalRequestUrl(url.trim()), [url]);
  const methodAllowsBody = method !== 'GET' && method !== 'HEAD';
  const canSend = localUrl && !sending;
  const responseContentType = response?.headers['content-type'];
  const displayedBody = response ? formatResponseBody(response.body, responseContentType) : '';

  const sendRequest = async (event: React.FormEvent) => {
    event.preventDefault();
    setError('');
    setResponse(null);
    setCopied(false);

    if (!isLocalRequestUrl(url.trim())) {
      setError('Use an HTTP(S) URL on localhost, 127.0.0.1, or ::1.');
      return;
    }

    let headers: Record<string, string>;
    try {
      const parsed = JSON.parse(headersText || '{}');
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('Headers must be a JSON object.');
      }
      if (Object.values(parsed).some(value => typeof value !== 'string')) {
        throw new Error('Every header value must be text.');
      }
      headers = parsed as Record<string, string>;
    } catch (parseError) {
      setError(parseError instanceof Error ? parseError.message : 'Headers must be valid JSON.');
      return;
    }

    const api = getCodetistApi();
    if (typeof api?.http?.requestLocal !== 'function') {
      setError('The local request host is unavailable. Open this plugin in the Codetist desktop app.');
      return;
    }

    setSending(true);
    try {
      const result = await api.http.requestLocal({
        method,
        url: url.trim(),
        headers,
        body: methodAllowsBody ? body : '',
      });
      setResponse(result as ApiResponse);
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : 'The local API request failed.');
    } finally {
      setSending(false);
    }
  };

  const copyResponse = async () => {
    if (!displayedBody) return;
    try {
      await navigator.clipboard.writeText(displayedBody);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      setError('Could not copy the response. Select and copy the text instead.');
    }
  };

  return (
    <main className="api-workbench">
      <header className="app-header">
        <div>
          <div className="eyebrow">LOCAL DEVELOPMENT</div>
          <h1>API Workbench</h1>
          <p>Send a request to a service running on your machine.</p>
        </div>
        <span className="local-badge"><span /> loopback only</span>
      </header>

      <form className="request-form" onSubmit={sendRequest}>
        <div className="url-row">
          <label className="sr-only" htmlFor="request-method">HTTP method</label>
          <select
            id="request-method"
            className={`method-select method-${method.toLowerCase()}`}
            value={method}
            onChange={event => setMethod(event.target.value as HttpMethod)}
          >
            {METHODS.map(item => <option key={item} value={item}>{item}</option>)}
          </select>
          <label className="sr-only" htmlFor="request-url">Local API URL</label>
          <input
            id="request-url"
            className="url-input"
            type="url"
            value={url}
            onChange={event => setUrl(event.target.value)}
            placeholder="http://localhost:3000/health"
            spellCheck={false}
            required
          />
          <button className="send-button" type="submit" disabled={!canSend}>
            {sending ? <><span className="spinner" /> Sending</> : 'Send'}
          </button>
        </div>
        {!localUrl && url.trim() && (
          <p className="url-hint">Only localhost and loopback URLs are allowed.</p>
        )}

        <div className="request-editors">
          <section className="editor-section">
            <label htmlFor="request-headers">Headers <span>JSON object</span></label>
            <textarea
              id="request-headers"
              value={headersText}
              onChange={event => setHeadersText(event.target.value)}
              rows={5}
              spellCheck={false}
              aria-label="Request headers as JSON"
            />
          </section>
          <section className="editor-section">
            <label htmlFor="request-body">
              Body <span>{method === 'GET' || method === 'HEAD' ? 'not used by this method' : 'text, up to 256 KB'}</span>
            </label>
            <textarea
              id="request-body"
              value={body}
              onChange={event => setBody(event.target.value)}
              rows={5}
              spellCheck={false}
              disabled={!methodAllowsBody}
              placeholder={'{\n  "message": "hello"\n}'}
              aria-label="Request body"
            />
          </section>
        </div>

        <div className="request-note">
          Requests are sent only when you press Send. Credentials and request data are not saved.
        </div>
      </form>

      <section className="response-section" aria-live="polite">
        <div className="response-heading">
          <h2>Response</h2>
          {response && (
            <div className="response-meta">
              <span className={`status-badge ${response.status >= 200 && response.status < 400 ? 'status-ok' : 'status-error'}`}>
                {response.status} {response.statusText}
              </span>
              <span>{response.durationMs} ms</span>
            </div>
          )}
        </div>

        {error && <div className="error-message" role="alert">{error}</div>}
        {!response && !error && !sending && (
          <div className="empty-response">Response details will appear here after you send a request.</div>
        )}
        {sending && <div className="empty-response">Waiting for the local service…</div>}
        {response && (
          <div className="response-content">
            <div className="response-url" title={response.url}>{response.url}</div>
            <details className="response-headers">
              <summary>Response headers <span>{Object.keys(response.headers).length}</span></summary>
              <pre>{JSON.stringify(response.headers, null, 2)}</pre>
            </details>
            <div className="body-heading">
              <span>Body</span>
              <button type="button" className="text-button" onClick={copyResponse} disabled={!displayedBody}>
                {copied ? 'Copied' : 'Copy'}
              </button>
            </div>
            <pre className="response-body">{displayedBody || '(empty response body)'}</pre>
          </div>
        )}
      </section>
    </main>
  );
}

export default App;
