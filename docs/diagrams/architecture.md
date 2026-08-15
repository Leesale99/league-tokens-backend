# Architecture Diagrams — League Tokens Backend

Rendered reference of the current `[Launch]` architecture. Source of truth:
`docs/specs/backend_system_design.md` + ADR-0001–0012.

## 1. System context — the edge and the VPS

```mermaid
flowchart LR
    player(["<b>Player client</b><br/>browser"])
    provider(["<b>External provider</b><br/>schedule · odds · results"])

    subgraph EDGE["Public edge"]
        cf["<b>Cloudflare</b><br/>free tier — edge cache · WAF · DDoS"]
        caddy["<b>Caddy</b><br/>TLS · auto-ACME · HSTS · per-IP rate-limit"]
    end

    subgraph VPS["Single VPS — Docker Compose (ADR-0006) · 1 core / 4 GB"]
        be["<b>backend</b><br/>one Go binary — modular monolith<br/>:8080 REST/JSON + SSE · :9100 metrics (internal)<br/>limits 1500 MB · 0.3 cpu"]
        pg[("<b>Postgres 16</b><br/>schema-per-context<br/>limits 1500 MB · 0.6 cpu")]
        bak["<b>backup sidecar</b><br/>one-shot pg_dump → rclone"]
    end

    obs["<b>Grafana Cloud</b><br/>Prometheus scrape · Tempo OTLP"]
    offsite["<b>Off-site bucket</b><br/>B2 / S3 — rclone target"]
    ghcr["<b>GHCR</b><br/>ghcr.io/league-tokens/backend:<sha>"]

    player -->|"HTTPS — REST/JSON commands + SSE real-time"| cf
    cf -->|"cached GETs / cache-bypass SSE"| caddy
    caddy -->|"plain HTTP on Compose network"| be
    be --> pg
    be -->|"HTTP poll every 30 s"| provider
    be -.->|"metrics :9100 · OTLP traces"| obs
    bak --> pg
    bak -.->|"daily dump · keep 7 d"| offsite
    ghcr -.->|"CI deploy — compose pull && up -d"| be

    classDef actor fill:#f1f5f9,stroke:#64748b,color:#0f172a;
    classDef edge fill:#eff6ff,stroke:#3b82f6,color:#1e3a8a;
    classDef svc fill:#f0fdf4,stroke:#16a34a,color:#14532d;
    classDef ext fill:#fdf4ff,stroke:#c026d3,color:#701a75;
    class player,provider actor;
    class cf,caddy edge;
    class be,pg,bak svc;
    class obs,offsite,ghcr ext;
    style VPS fill:#f8fafc,stroke:#cbd5e1,color:#334155;
    style EDGE fill:#eff6ff,stroke:#93c5fd,color:#1e3a8a;
```

## 2. Inside the monolith — bounded contexts + shared kernel

```mermaid
flowchart TB
    main["<b>cmd/server/main.go</b><br/>the only file importing more than one context — wires everything"]

    subgraph CTX["Bounded contexts — one Go package each; contexts never import each other (ADR-0008)"]
        direction LR
        identity["<b>identity</b><br/>users · sessions · signing keys<br/>Ed25519 ×2 · Argon2id · JWT"]
        schedule["<b>schedule</b><br/>raw feed rows · results<br/>teams · rounds · matches"]
        game["<b>game</b><br/>engine state machines<br/>Season · Round · Ride · acc · Team.base"]
        ledger["<b>ledger</b><br/>double-entry journal · balances<br/>wallets · reserve · CommonPool"]
        rankings["<b>rankings</b><br/>read-model projections<br/>player_TB · team_basket · boards"]
        market["<b>market</b><br/>order book · matching engine<br/>dormant at Launch"]
    end

    feed["<b>feed</b><br/>stateless upstream poll adapter"]
    edge["<b>http edge</b><br/>router · middlewares<br/>auth · rate-limit · idempotency<br/>SSE broker · problem+json (ADR-0011)"]

    subgraph K["infra — shared kernel"]
        bus["<b>bus</b><br/>outbox relay → in-process Go channels"]
        sched["<b>scheduler</b><br/>deadline store · at-most-once fire"]
        tel["<b>telemetry</b><br/>slog · prometheus · OTel"]
        dec["<b>dec</b><br/>decimal · round-half-up · lint-banned ops"]
        db["<b>db</b><br/>sqlc fileset per context · migrations"]
        cfg["<b>config</b><br/>env-driven · strict Validate()"]
        err["<b>apperr</b><br/>typed errors · RFC 7807"]
    end

    main --> identity & schedule & game & ledger & rankings & market & edge & feed

    feed -->|"writes via SchedulePort"| schedule
    schedule -->|"results via ScheduleReadPort"| game
    game -->|"intent commands — Lock · Burn · ReserveBuy · GrantCurrency<br/>synchronous, same Postgres tx"| ledger
    ledger -->|"accepted / rejected"| game
    identity -.->|"JWT issue + verify"| edge
    identity & schedule & game & ledger & rankings & market & feed & edge -.- infra
    bus -->|"events"| rankings
    bus -->|"events"| market
    bus -->|"events"| sse["<b>SSE broadcast</b>"]
    sched -->|"cutoff_fired"| game

    classDef composer fill:#0f172a,color:#f8fafc,stroke:#0f172a;
    classDef ctx fill:#eff6ff,stroke:#3b82f6,color:#1e3a8a;
    classDef dormant fill:#fafafa,stroke:#a1a1aa,color:#52525b;
    classDef kernel fill:#f0fdf4,stroke:#16a34a,color:#14532d;
    classDef aux fill:#fff7ed,stroke:#ea580c,color:#7c2d12;
    class main composer;
    class identity,schedule,game,ledger,rankings ctx;
    class market dormant;
    class feed,edge,sse aux;
    class bus,sched,tel,dec,db,cfg,err kernel;
    style CTX fill:#f8fafc,stroke:#cbd5e1,color:#334155;
    style K fill:#f0fdf4,stroke:#86efac,color:#14532d;
```

## 3. Data flow — one round, end to end

```mermaid
flowchart LR
    P["<b>External provider</b><br/>schedule · odds · results"] -->|"poll 30 s"| F["<b>feed</b>"]
    F -->|"WriteResult"| S["<b>schedule</b>"]
    S -->|"ResultAvailable (outbox)"| G["<b>game</b> — ResolveMatch"]
    G -->|"intent commands"| L["<b>ledger</b>"]
    G -->|"domain events (outbox)"| R["<b>rankings</b>"]
    G -->|"events (outbox)"| E["<b>SSE broker</b>"]
    G & L -->|"same Postgres tx"| PG[("Postgres")]
    R -->|"boards · standings"| E

    classDef svc fill:#eff6ff,stroke:#3b82f6,color:#1e3a8a;
    classDef data fill:#f0fdf4,stroke:#16a34a,color:#14532d;
    class F,S,G,L,R,E svc;
    class PG data;
```
