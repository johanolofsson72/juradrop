# Code style and conventions

## C# / .NET

- Follow official [C# Coding Conventions](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions).
- PascalCase for public members, methods, and classes.
- camelCase for local variables and private fields.
- Prefix private fields with `_` (e.g., `_logger`).
- Use `var` when the type is obvious from the right side.
- One class per file. Filename matches class name.
- Use `nullable reference types` (enable in .csproj).
- Prefer `record` for immutable data types.
- File-scoped namespaces (`namespace X;` instead of `namespace X { }`).
- Primary constructors where appropriate (e.g., services with dependency injection).
- Expression-bodied members for simple implementations.
- Structure with classes and methods — never use `#region`.

## JavaScript / jQuery

- Use `const` and `let` — never `var`.
- camelCase for variables and functions.
- Prefer modern DOM APIs when jQuery is not already used in the file.
- Strict equality (`===`) always.

## HTML / CSS

- Semantic HTML5.
- BEM naming for CSS classes where appropriate.
- Mobile-first responsive design.
- Use CSS classes — never inline `style="..."`.

## WordPress

- Follow [WordPress Coding Standards](https://developer.wordpress.org/coding-standards/).
- Use child themes and hooks — never modify core files.

## General principles

- Code should be readable without comments — good naming is usually enough.
- Only add comments where the logic is not obvious.
- Keep methods short and focused — one method does one thing.
- Prefer explicit over implicit.
- Error messages should be clear and actionable.
- Keep UI thin — all business logic in services.

## File structure

- Separate concerns: Models, Views, Controllers, Services.
- Shared components in `Shared/` or `Components/`.
- In .NET projects: `wwwroot/` for web-specific files.
- Static assets always in `assets/` in the project root.

## Database (SQLite)

- Entity Framework Core with SQLite provider.
- Code-first with migrations.
- Do not include `.db` files in git.
- Seed data via migrations or separate seed method.
