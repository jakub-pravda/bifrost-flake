flake:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.bifrost;

  defaultPackage =
    flake.packages.${pkgs.stdenv.hostPlatform.system}.bifrost or
      (throw "bifrost: no package for ${pkgs.stdenv.hostPlatform.system}");

  args =
    [ "-app-dir"    cfg.dataDir
      "-host"       cfg.host
      "-port"       (toString cfg.port)
      "-log-level"  cfg.logLevel
      "-log-style"  cfg.logStyle
    ] ++ cfg.extraArgs;

  configFile = if cfg.settings != null
    then (pkgs.formats.json {}).generate "bifrost-config.json" cfg.settings
    else null;
in
{
  options.services.bifrost = {
    enable = lib.mkEnableOption "Bifrost AI gateway";

    package = lib.mkOption {
      type        = lib.types.package;
      default     = defaultPackage;
      description = "The bifrost-http binary to use.";
    };

    host = lib.mkOption {
      type        = lib.types.str;
      default     = "127.0.0.1";
      description = "Address the HTTP server binds to.";
    };

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8080;
      description = "Port the HTTP server listens on.";
    };

    dataDir = lib.mkOption {
      type        = lib.types.path;
      default     = "/var/lib/bifrost";
      description = "Directory for Bifrost state (config, database).";
    };

    logLevel = lib.mkOption {
      type        = lib.types.enum [ "debug" "info" "warn" "error" ];
      default     = "info";
      description = "Log verbosity.";
    };

    logStyle = lib.mkOption {
      type        = lib.types.enum [ "pretty" "json" ];
      default     = "json";
      description = "Log output format.";
    };

    openFirewall = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = "Open the firewall for the configured port.";
    };

    environmentFile = lib.mkOption {
      type        = lib.types.nullOr lib.types.path;
      default     = null;
      description = ''
        Path to a file containing environment variables (one KEY=value per line).
        Useful for supplying provider API keys that Bifrost config can reference.
      '';
    };

    settings = lib.mkOption {
      type    = lib.types.nullOr (pkgs.formats.json {}).type;
      default = null;
      example = lib.literalExpression ''
        {
          mcp.client_configs = [
            {
              name            = "filesystem";
              connection_type = "stdio";
              stdio_config    = {
                command = "npx";
                args    = [ "-y" "@anthropic/mcp-filesystem" ];
                envs    = [ "HOME" "PATH" ];
              };
              tools_to_execute = [ "*" ];
            }
          ];
        }
      '';
      description = ''
        Declarative <filename>config.json</filename> for Bifrost, expressed as a
        Nix attribute set.  When non-null the value is serialised to JSON and
        written to <option>dataDir</option>/config.json before the service
        starts, replacing any file already there.

        See <link xlink:href="https://docs.getbifrost.ai"/> for the full schema.
        Secrets (API keys, bearer tokens) should be supplied via
        <option>environmentFile</option> and referenced as
        <literal>env.MY_VAR</literal> inside connection strings — do not embed
        them directly in this option.
      '';
    };

    extraArgs = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = "Extra arguments forwarded to bifrost-http.";
    };

    user = lib.mkOption {
      type    = lib.types.str;
      default = "bifrost";
    };

    group = lib.mkOption {
      type    = lib.types.str;
      default = "bifrost";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = lib.mkIf (cfg.user == "bifrost") {
      isSystemUser = true;
      group        = cfg.group;
      description  = "Bifrost gateway daemon user";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "bifrost") {};

    systemd.services.bifrost = {
      description = "Bifrost AI gateway";
      after       = [ "network-online.target" ];
      wants       = [ "network-online.target" ];
      wantedBy    = [ "multi-user.target" ];

      serviceConfig = {
        Type        = "simple";
        User        = cfg.user;
        Group       = cfg.group;
        ExecStartPre = lib.optional (cfg.settings != null)
          "${pkgs.coreutils}/bin/install -m600 ${configFile} ${cfg.dataDir}/config.json";
        ExecStart   = lib.escapeShellArgs ([ "${cfg.package}/bin/bifrost-http" ] ++ args);
        Restart     = "on-failure";
        RestartSec  = 5;

        # State directory — systemd creates /var/lib/bifrost owned by the service user.
        StateDirectory         = "bifrost";
        StateDirectoryMode     = "0700";
        WorkingDirectory       = cfg.dataDir;

        # Optional secrets file
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;

        # Hardening
        NoNewPrivileges          = true;
        ProtectSystem            = "strict";
        ProtectHome              = true;
        PrivateTmp               = true;
        ProtectKernelTunables    = true;
        ProtectControlGroups     = true;
        RestrictNamespaces       = true;
        RestrictAddressFamilies  = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        # Not setting MemoryDenyWriteExecute — Go runtime may need W+X pages.
      };
    };

    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
