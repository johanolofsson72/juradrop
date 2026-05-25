# Project template

Template for project-specific sections. **IMPORTANT:** Fill in ALL sections below at project start — repo-specific customization yields 2x better results (source: Arize ML).

## Core principles (non-negotiable)

Project-specific principles that must NEVER be broken:

1. [FILL IN: e.g., "All data access MUST be tenant-scoped"]
2. [FILL IN: e.g., "JWT tokens MUST be stored in sessionStorage, never cookies"]

## Project description

**Project name**: [FILL IN]
**Purpose**: [FILL IN: short description of what the system does and for whom]
**Design document**: [FILL IN: path to visual design guide, or remove this line]

## Architecture

Describe the system components with an ASCII diagram:

```text
[FILL IN: ASCII diagram]

Example:
┌─────────────┐     ┌─────────────┐
│  Frontend   │────▶│   Backend   │
│  (Blazor)   │     │  (Web API)  │
└─────────────┘     └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   SQLite    │
                    └─────────────┘
```

## Mandatory directories

The following directories should **always** be created in new projects:

- `src/` — all source code
- `tests/` — all tests
- `legacy/` — old files and code being phased out
- `artifacts/` — build output, reports, and generated files
- `temp/` — temporary files (should be in `.gitignore`)

## Typical project profiles

Projects are often large fullstack applications with frontend, backend, databases, and authentication. .NET backend + SQLite, often connected to course/project websites.

**Learnways integration**: Backend is often connected to a website built by [Learnways](https://learnways.com) (partner) in plain HTML, CSS, and JavaScript.

## Key patterns

Document the project's central patterns so Claude writes idiomatic code:

- **Authentication**: [FILL IN: e.g., JWT in sessionStorage, Identity + cookies, OAuth]
- **Database access**: [FILL IN: e.g., EF Core repositories, `$wpdb->prepare()`, direct SQL]
- **API patterns**: [FILL IN: e.g., Minimal API with `Result<T>`, MVC controllers]
- **Error handling**: [FILL IN: e.g., `Result<T, Exception>`, ProblemDetails]
- **State management**: [FILL IN: e.g., Blazor cascading parameters, Redux]
- **Domain terms**: [FILL IN: business terms and acronyms used in the codebase]

## Local development environment

**Start command:**

```bash
# [FILL IN: e.g., dotnet run --project src/AppHost]
```

**URLs:**

- Frontend: [FILL IN: e.g., https://localhost:5001]
- Admin: [FILL IN: if applicable]

**Known workarounds:**

- [FILL IN: any issues with IPv6, memory, ports, certificates, etc.]
