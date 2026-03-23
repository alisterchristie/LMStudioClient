# LMStudioClient

A minimal Delphi VCL desktop application that streams responses from a locally running [LM Studio](https://lmstudio.ai) instance and renders them as formatted Markdown.

## Features

- Sends prompts to any locally running OpenAI-compatible LLM server
- Streams the response token-by-token as it arrives rather than waiting for the full reply
- Renders the response as formatted Markdown (headings, bold, italic, code blocks, tables, lists, blockquotes, strikethrough, horizontal rules) via an embedded WebView2 browser
- Configurable host and port, persisted between sessions

## Requirements

- Windows 10/11
- [RAD Studio 12](https://www.embarcadero.com/products/rad-studio) (Delphi, Win32 target)
- [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (included with Windows 11; available as a free download for Windows 10)
- [LM Studio](https://lmstudio.ai) running locally with a model loaded and the local server started

## Building

Open `LMClient.dproj` in RAD Studio and use **Run > Build** (Shift+F9), or from the command line:

```
msbuild LMClient.dproj /p:Config=Debug /p:Platform=Win32
```

Output: `Win32\Debug\LMClient.exe`

## Usage

1. Start LM Studio, load a model, and enable the local server (default: `localhost:1234`).
2. Run `LMClient.exe`.
3. Adjust the **Host** and **Port** fields if your LM Studio server is not on the default address.
4. Type a prompt in the text area and click **Ask**.
5. The response streams in and is rendered as Markdown in real time.

## Architecture

The application consists of two units:

### `formLMClient.pas`

The main VCL form (`TfrmLMClient`). Responsibilities:

- Builds the OpenAI-compatible chat completions JSON request body
- Writes a skeleton HTML page (with embedded CSS and a JavaScript Markdown renderer) to a temp file and navigates the embedded browser to it
- Creates a `TStreamThread` and wires up chunk and done callbacks
- On each chunk callback, appends the text to an accumulator and updates the browser via `ExecuteScript`
- Persists host/port settings to an INI file alongside the executable

### `StreamThread.pas`

A `TThread` subclass that performs the HTTP streaming. Responsibilities:

- Opens an HTTP connection using the WinHTTP API (`winhttp.dll`) directly — this allows chunk-by-chunk reading, which `TNetHTTPClient` does not support
- POSTs the request to `/v1/chat/completions` with `"stream": true`
- Reads the Server-Sent Events (SSE) response line by line, parses each `data: {...}` JSON chunk, and extracts `choices[0].delta.content`
- Delivers each text chunk to the main thread via `TThread.Synchronize`
- Signals completion via `TThread.Queue` once the stream ends
- Supports cancellation: `Cancel` calls `Terminate` and closes the WinHTTP session handle to unblock any pending read

### Markdown rendering

Rather than depending on a CDN-hosted library, the HTML page written at stream start embeds a self-contained JavaScript Markdown renderer. It supports fenced code blocks, headings (h1–h6), bold, italic, strikethrough, inline code, unordered and ordered lists, tables, blockquotes, and horizontal rules. Content is passed to the renderer via `ExecuteScript('update(...)')` on each chunk, updating the page DOM in place.
