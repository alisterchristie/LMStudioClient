# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A minimal Delphi VCL desktop application that sends prompts to a locally running LM Studio instance and displays the response. The app targets Win32.

## Build

Open `LMClient.dproj` in Embarcadero RAD Studio and use **Run > Build** (or Shift+F9). The project uses MSBuild internally; you can also build from the command line:

```
msbuild LMClient.dproj /p:Config=Debug /p:Platform=Win32
```

Output is placed in `Win32\Debug\LMClient.exe`.

## Architecture

The entire application is a single form (`formLMClient.pas` / `formLMClient.dfm`):

- **`Memo1`** — user types the prompt here (default text: "Write me a story")
- **`Button1`** — clicking it calls `AskLMStudio(Memo1.Text)` synchronously
- **`mmoResponse`** — displays the returned text

`AskLMStudio` builds an OpenAI-compatible chat-completions JSON request and POSTs it to `http://localhost:1234/v1/chat/completions` using `TNetHTTPClient` (RTL unit `System.Net.HttpClient`). The response timeout is 3 minutes. It parses `choices[0].message.content` from the JSON response and returns it as a plain string.

**Key constraint:** the HTTP call runs on the main thread (blocking the UI). LM Studio must be running locally on port 1234 before the button is clicked.

## TEdgeBrowser (WebView2) Notes

- `NavigateToString` does **not** work in this project — use `Navigate` with a `file:///` URL instead.
- Pattern for dynamic HTML: write to a temp file with `TFile.WriteAllText`, then call `Navigate('file:///' + StringReplace(path, '\', '/', [rfReplaceAll]))`.
- Markdown is rendered via an inline JS renderer embedded in the HTML (no CDN dependency). It handles fenced code blocks, headers, bold/italic, inline code, and unordered lists.
- Content is passed via `TJSONString.ToJSON` (safe escaping of quotes/backslashes) with an additional `</` → `<\/` substitution to prevent breaking the `<script>` block.

## Delphi/VCL Notes

- Form file is `formLMClient.dfm`; edit visually in the IDE form designer or as text.
- JSON handling uses `System.JSON` (RTL built-in — `TJSONObject`, `TJSONArray`, `TJSONNumber`).
- HTTP uses `System.Net.HttpClient` / `System.Net.HttpClientComponent` (RTL built-in, no third-party libs).
- Project version targets RAD Studio 12 (ProjectVersion 20.3).
