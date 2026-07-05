---
name: notebook-inspection
description: Inspect, search, edit, review, debug, or summarize Jupyter notebooks without loading noisy .ipynb JSON. Use when Codex works with .ipynb files, or when broad source searches may cross notebook-heavy trees with large outputs, embedded images, base64 blobs, Plotly HTML, widget state, execution metadata, stored tracebacks, or generated plots.
---

# Notebook Inspection

Use this skill to work with notebooks through their source cells first, not
through raw JSON dumps.

## Default Rule

Do not read an entire `.ipynb` file directly unless the task specifically
requires notebook outputs or metadata. Jupyter notebooks are JSON and often
contain large outputs, embedded images, base64 data, Plotly HTML, widget state,
execution metadata, and other context noise.

Prefer the bundled script:

```sh
python3 <skill-dir>/scripts/notebook_inspect.py <command> ...
```

If the repository uses `uv`, run it through `uv run python` and follow
`$uv-sandbox-workflow` for Codex sandbox cache setup.

## First Pass

1. Identify relevant notebooks:

   ```sh
   rg --files -g '*.ipynb'
   ```

2. Inspect notebook size and output burden before opening large files:

   ```sh
   python3 <skill-dir>/scripts/notebook_inspect.py stats notebooks
   ```

3. Inspect code cells only:

   ```sh
   python3 <skill-dir>/scripts/notebook_inspect.py cells --type code path/to/notebook.ipynb
   ```

4. Inspect markdown cells only when prose, headings, or explanations matter:

   ```sh
   python3 <skill-dir>/scripts/notebook_inspect.py cells --type markdown path/to/notebook.ipynb
   ```

5. Read outputs only when the user asks about rendered figures, stored results,
   error tracebacks, visual notebook state, or cleaning outputs.

## Searching

For broad source searches where notebooks are not the target, exclude raw
notebook JSON so embedded base64 images or HTML output do not flood the result:

```sh
rg -n -g '!*.ipynb' "symbol_or_text" path/to/search
```

Search notebook source cells instead of raw JSON:

```sh
python3 <skill-dir>/scripts/notebook_inspect.py search "symbol_or_text" notebooks
```

Use `--type markdown` when searching prose and `--type all` when both code and
markdown are relevant.

## Outputs

Only inspect outputs when necessary. Start with text streams, tracebacks, and
small text/plain or text/markdown payloads:

```sh
python3 <skill-dir>/scripts/notebook_inspect.py outputs path/to/notebook.ipynb
```

Do not copy large base64 strings, embedded JavaScript, Plotly blobs, widget
state, or binary image data into chat, plans, or source comments. Summarize that
such outputs exist instead.

## Editing

Prefer changing reusable library code and keeping notebooks thin. If the
notebook itself must change:

- edit the smallest relevant set of cells;
- preserve intentional narrative text, figure captions, and parameter choices;
- do not normalize formatting across the whole notebook unless formatting is
  the task;
- avoid committing large regenerated outputs unless the user specifically wants
  them;
- record command, data source, random seed, and important parameters for
  generated artifacts.

After editing, validate notebook JSON:

```sh
python3 <skill-dir>/scripts/notebook_inspect.py validate path/to/notebook.ipynb
```

If the repo has notebook execution tooling, use it when execution is required.
Otherwise do not claim the notebook was executed.

## Generated Artifacts

Treat notebooks, plots, generated markdown, and example outputs as artifacts,
not as the primary implementation surface.

- Inspect only artifacts relevant to the task.
- Prefer code-level tests when they prove the behavior.
- Avoid committing large regenerated outputs unless the user asks or repo
  convention requires it.
- Prefer fixtures or small synthetic data for tests.
- If external data is required, document where it is expected to live and how
  failure should look when it is missing.
- Make generated plots deterministic when practical by recording commands, data
  sources, random seeds, and important parameters.

## Cleaning Outputs

Do not strip notebook outputs unless the user asks or repo convention requires
it. Prefer the repo's existing notebook tooling when present. If no tooling
exists, use a small script that clears only outputs and execution counts, then
validate that the notebook still parses.

## Validation Choices

Use code-level tests when they prove the behavior. Execute notebooks only when
the notebook is itself the artifact being fixed or demonstrated. If execution
depends on optional data or long-running computation, state that limitation and
run a smaller reproducer or focused test instead.
