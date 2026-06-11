# UI State Matrix｜LuckyCat Skin

| Business state | Effective UI state | Global lamp | Compact chip | Sound |
|---|---|---|---|---|
| `blocked` | blocked | red | 阻塞 | red |
| `stale` | blocked diagnostic | red | 阻塞 | red lane if emitted |
| `running` | running | blue | 运行 | none |
| `queued` | running | blue | 运行 | none |
| `done_unverified` | pending verify | blue | 待验 | none |
| `done_verified` | verified done | green only if no active/observed | 完成 | green |
| `observed_active` | live observed | blue | 观察 | none |
| `observed_quiet` | weak observed | blue or hidden | 观察 | none |
| `observed_disappeared` | removed | no effect | none | none |
| no task | idle | gray | 空闲 | none |

## Global Priority

1. managed blocked/stale → red
2. high-confidence observed_attention → red
3. running/queued/done_unverified/observed_active → blue
4. done_verified only and nothing active → green
5. empty → gray
