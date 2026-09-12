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

### Catching `Exception`: say what you mean about `OutOfMemoryException`

`OutOfMemoryException` is not an ordinary failure. Catching it, logging it as a routine error and
carrying on means the next allocation walks into the same wall, while the log says "parse failed"
when the truth is that the process is out of memory. A broad catch in `src/` has to say which of
two things it meant.

On a parse path, exclude it. If the guarded code is reading, decoding or building something whose
whole job is to allocate, an OOM there is that operation's own failure mode, and it should reach
the host:

```csharp
catch (Exception ex) when (ex is not OutOfMemoryException)
```

Naming the failures you expect works too, since OOM then cannot arrive:

```csharp
catch (Exception ex) when (ex is IOException or JsonException)
```

In a background loop, swallow it, on the record. Housekeeping must never take the host down, so a
`BackgroundService` catching everything is right. But each such site belongs in an explicit
exemption list with a written reason, enforced by a convention test over `src/`.

Keep that list in the test, never as a marker comment beside the catch. A comment at the catch site
would be self-granting: the code that wants the exemption would also be the code that grants it.
Getting on the list has to be a second, separate edit in a file whose job is to say no.

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
