# sbnd-wirecell-production

Workflow steering for SBND Wire-Cell production.

- [`aurora/`](aurora/README.md): reco1 → Wire-Cell 2-step chain → merged into the flat CAF as `recTreeWireCell` (ai-helper issue 39). Agents: read [`aurora/AGENTS.md`](aurora/AGENTS.md).
- [`validation-xin/`](validation-xin/README.md): the (run, subrun, event) lists of the MC and data events Xin uses for evaluation — exclude them from ML training.
