# bifrost-flake

Nix flake packaging [Bifrost](https://github.com/maximhq/bifrost) — an AI gateway.

This flake provides:

- **`packages.<system>.bifrost`** — the upstream static `bifrost-http` binary
  (x86_64-linux, aarch64-linux).
- **`nixosModules.bifrost`** — a hardened systemd service with declarative configuration.

## Usage

Run it ad hoc:

```console
nix run github:jakub-pravda/bifrost-flake
```

Enable the NixOS service:

```nix
{
  inputs.bifrost.url = "github:jakub-pravda/bifrost-flake";

  outputs = { nixpkgs, bifrost, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        bifrost.nixosModules.bifrost
        {
          services.bifrost = {
            enable = true;
            port = 8080;
            # Provider API keys, referenced from config as env.OPENAI_API_KEY
            environmentFile = "/run/secrets/bifrost.env";
          };
        }
      ];
    };
  };
}
```

Then point any OpenAI client at `http://127.0.0.1:8080`, or open the web UI at the same
address to configure providers.

