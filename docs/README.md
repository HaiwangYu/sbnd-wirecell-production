# Productions page (GitHub Pages)

`index.html` renders `productions.js`. The page is served from this `docs/` folder on `main` (Settings → Pages → Deploy from a branch → `main` / `/docs`).

## Updating

Edit **only** `productions.js`; `index.html` builds every section from it.

- **New production:** add one entry to `productions` with:
  - `id`, `species` (a key from `species`), `side` (`training` = Aurora, `evaluation` = FNAL);
  - `config` (a key from `configs`), `site`, `title`;
  - `date` (`YYYY-MM-DD`, the finish date; a running job may say `YYYY-MM-DD (submitted)`);
  - `issues` (`prod#N` for this repo, `aih#N` for wire-cell-toolkit-ai-helper);
  - `input`, `events`, `events_wc`, `units`, `output`, `size`;
  - `status` (`available` | `partial` | `running` | `unverified` | `deleted`), plus `status_note` and `note`.
    - `available`: the merged outputs exist and under 1% of events lack Wire-Cell output. Evictable scratch products go in `status_note`.
    - `partial`: 1% or more of events failed, or the main outputs were deleted.
- **Current vs history:** the page shows the two latest single-species entries per species and side as current. Everything older goes to history automatically.
  - A multi-sample round (`species` given as a list) always goes to history.
- **New configuration:** add it to `configs` under a short label.
  - FermiGrid labels are `fg<N>`, Aurora labels `aurora-r<N>`. Older FNAL rounds keep their names (`r3` … `r8`).
  - Reuse an existing label only when the chain, the builds and the key knobs are the same.
- **Data deleted or moved:** change `status` and `status_note`, and say in `status_note` when and where it was recorded.
- **Overlaps:** add any training/evaluation overlap fact to `overlaps`.
- Set `updated` to the date of the edit.

Every number should trace back to an issue comment. The sources are:
- https://github.com/HaiwangYu/sbnd-wirecell-production/issues
- https://github.com/HaiwangYu/wire-cell-toolkit-ai-helper/issues
