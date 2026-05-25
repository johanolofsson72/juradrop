# Git conventions

## Commit messages

Write commit messages in **English** with the following format:

```
<type>: <short description>
<optional longer explanation>
```

### Types

- `feat`: New functionality
- `fix`: Bug fix
- `refactor`: Restructuring without behavior change
- `test`: Addition or modification of tests
- `docs`: Documentation
- `style`: Formatting, semicolons, etc. (no code change)
- `chore`: Build scripts, dependencies, configuration

### Examples

```
feat: Add login page with form validation
Implements the login form with client and server validation.
Uses ASP.NET Identity for authentication.
```

## Branches

- `main` — stable production code
- `develop` — active development
- `feature/<description>` — new functionality
- `fix/<description>` — bug fix

## Pull requests

- Title in English, short and descriptive.
- Describe what and why in the PR description.
- Link to relevant issues if any exist.
