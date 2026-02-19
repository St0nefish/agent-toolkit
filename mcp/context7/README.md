# Context7 MCP Server

Provides version-specific library documentation at query time via two MCP tools:

- **`resolve-library-id`** — look up a library by name, returns a Context7 library ID
- **`get-library-docs`** — fetch docs and code examples for a resolved library ID

## What it indexes

Context7 indexes **public library documentation** — API references, setup guides,
configuration docs, and code examples — scraped and kept up to date from source
repos and official doc sites. Coverage spans thousands of libraries across
ecosystems including (not exhaustive):

- **JavaScript / TypeScript** — React, Next.js, Vue, Svelte, Node.js, Bun, etc.
- **Python** — FastAPI, Django, Flask, pandas, LangChain, etc.
- **Java / Kotlin** — Spring, Gradle, Android SDK, etc.
- **Go, Rust, Ruby, PHP, C#/.NET** — major frameworks and standard libraries
- **Databases & infra** — PostgreSQL, MongoDB, Redis, Supabase, Prisma, etc.
- **Cloud & DevOps** — AWS SDK, Cloudflare Workers, Docker, Terraform, etc.

Browse the full library list at <https://context7.com/libraries>.
Anyone can submit new libraries via <https://context7.com/add-library>.

Private/internal library documentation is not supported.

## Transport

Uses the hosted HTTP endpoint — no local runtime (no Node.js, no Docker).

## Licensing

The MCP server code is MIT-licensed, and the hosted API has a free tier.
**Enterprise use requires a paid license** — this deployment is for personal use only.
