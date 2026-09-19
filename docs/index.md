# Maned

Maned is an integer-only dataflow language (`.mnd`) for linear algebra and
small ML workloads. A program declares its quantization contract, its inputs
and outputs, and a set of `calc::lambda_flow` dataflow graphs written in RPN.
The toolchain runs them locally, serves them as an HTTP API, or offloads them
to remote workers — with bit-exact, reproducible integer results everywhere.

Bit-exact means what it says: the same program on an Apple Silicon Mac, an
x86-64 Linux box and an ARM server produces identical output, byte for byte.
Every release is gated on that before it ships.

## Install

```sh
curl -fsSL https://fabianodicheti.github.io/maned/install.sh | sh
```

Or with Homebrew:

```sh
brew install fabianodicheti/maned/maned
```

The installer downloads a prebuilt tarball for your machine, verifies its
SHA-256 against the release manifest, and puts three binaries in
`~/.local/bin` (or `/usr/local/bin` if you can write there). It never calls
`sudo` and never edits your shell configuration.

Options: `--version X.Y.Z`, `--prefix DIR`, `--dry-run`, `--uninstall`.

```sh
curl -fsSL https://fabianodicheti.github.io/maned/install.sh | sh -s -- --prefix ~/.local
```

## The tools

| Tool | Purpose |
|---|---|
| `maned-run` | run a `.mnd` program — locally or on remote workers; `--verify` re-runs locally and compares exactly |
| `maned-serve` | serve one `.mnd` script as an HTTP API (`/health`, `/run`, `/run.json`, `/frame`, `/frame.csv`) |
| `maned-lint` | static checks with editor-parseable diagnostics |

A run can also be frozen: `maned-run --bundle out.sh script.mnd` writes a
self-contained shell bundle carrying the script, its inputs and a hash
manifest, so the same program can be replayed elsewhere.

## Supported platforms

| | |
|---|---|
| macOS 11+ | Apple Silicon and Intel, one universal binary |
| Linux x86-64 | glibc 2.35+ (Ubuntu 22.04+, Debian 12+) |
| Linux ARM64 | glibc 2.35+ |

**Windows is not supported.** This is a decision, not an oversight — use WSL,
where the Linux x86-64 build works as-is. Alpine and other musl systems are
not supported either; the binaries link glibc.

## Documentation

The language guide, the CLI reference and the diagnostic codes:

https://fabianodicheti.github.io/maned-lang-docs/

## Quick taste

Maned is postfix: no operator precedence, no parentheses. The token order *is*
the dependency order, which is what makes a program map directly onto a
dataflow graph.

```sh
cat > hello.mnd <<'EOF'
mnd::quantmax=1000;
mnd::quantmin=-1000;
mnd::quantres=0;

in::a = 2;
in::b = 3;
in::c = 4;

calc::lambda_flow arithmetic(a, b, c) {
    a b add c mul sum_then_scale =   # (2 + 3) * 4 = 20
    b c mul a add scale_then_sum =   # 2 + (3 * 4) = 14
} return sum_then_scale, scale_then_sum;
EOF

maned-run hello.mnd
```

```
flow 'arithmetic' outputs:
sum_then_scale : scalar = 20
scale_then_sum : scalar = 14
```

Same three values, same three operators — only the token order differs. In an
infix language that distinction needs parentheses.

## Licence

Maned is **free to use for any purpose, including commercial use in
production**, at no cost and with no registration.

It is **not open source**. The source is not published, and the licence does
not permit redistributing the binaries or reverse engineering them. See
[LICENSE](LICENSE) for the full terms and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the one third-party
component.

## Reporting problems

Issues are welcome at https://github.com/FabianoDicheti/maned/issues. Include
the output of `maned-run --version`, your OS and architecture, and the smallest
`.mnd` program that reproduces the problem.
