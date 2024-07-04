# Electric

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `electric` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:electric, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/electric>.

## Running

Run Postgres:

```sh
docker compose -f dev/docker-compose.yml create
docker compose -f dev/docker-compose.yml start
```

Source the `.env.dev` somehow, e.g.:

```sh
set -a; source .env.dev; set +a
```

Run the Elixir app:

```sh
iex -S mix
```
