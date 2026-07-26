# Home Manager module exposing `services.lightpanda`.
# Consumed as: inputs.lightpanda.homeModules.default
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.lightpanda;
  args =
    [
      "serve"
      "--host"
      cfg.host
      "--port"
      (toString cfg.port)
    ]
    ++ cfg.extraArgs;
in
{
  options.services.lightpanda = {
    enable = lib.mkEnableOption "the Lightpanda headless-browser CDP server (systemd user service)";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "lightpanda.packages.\${system}.default";
      description = "The lightpanda package to run.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host the CDP server binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9222;
      description = "Port the CDP server listens on.";
    };

    disableTelemetry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set LIGHTPANDA_DISABLE_TELEMETRY=true for the service.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--disable-metrics" ];
      description = "Extra arguments appended to `lightpanda serve`.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.lightpanda = {
      Unit = {
        Description = "Lightpanda headless browser CDP server";
        After = [ "network.target" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        ExecStart = "${lib.getExe cfg.package} ${lib.escapeShellArgs args}";
        Restart = "on-failure";
        RestartSec = 2;
      }
      // lib.optionalAttrs cfg.disableTelemetry {
        Environment = [ "LIGHTPANDA_DISABLE_TELEMETRY=true" ];
      };
    };
  };
}
