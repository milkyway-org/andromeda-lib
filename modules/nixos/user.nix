args @ {
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) types mkOption mkDefault foldl optionalAttrs optional;
  inherit (lib.andromeda.module) mkOpt' mkBoolOpt;

  cfg = config.andromeda;
  inputs = args.inputs or {};
  user-names = builtins.attrNames cfg.user;

  create-system-users = system-users: name: let
    user = cfg.user.${name};
  in
    system-users
    // (optionalAttrs user.create {
      ${name} = {
        name = mkDefault name;
        group = mkDefault "users";
        home = mkDefault user.home.path;
        extraGroups = optional user.admin "wheel";
        isSystemUser = mkDefault user.isSystemUser;
        isNormalUser = mkDefault (!user.isSystemUser);
      };
    });
in {
  options.andromeda = with types; {
    user = mkOption {
      default = {};
      description = "User configuration.";

      type = attrsOf (submodule ({name, ...}: {
        options = {
          create = mkBoolOpt true "Whether to create the user automatically.";
          isSystemUser = mkBoolOpt false "Whether the user should be a system user.";
          admin = mkBoolOpt true "Whether the user should be added to the wheel group.";

          home = {
            enable = mkBoolOpt true "Whether to enable home-manager for this user.";
            path = mkOpt' str "/home/${name}";

            config = mkOption {
              default = {};

              # HM-compatible options taken from:
              # https://github.com/nix-community/home-manager/blob/0ee5ab611dc1fbb5180bd7d88d2aeb7841a4d179/nixos/common.nix#L14
              # This has been adapted to support documentation generation without
              # having home-manager options fully declared.
              type = types.submoduleWith {
                specialArgs =
                  {
                    osConfig = config;
                    modulesPath = "${inputs.home-manager or "/"}/modules";
                  }
                  // (config.home-manager.extraSpecialArgs or {});

                modules =
                  [
                    ({
                      lib,
                      modulesPath,
                      ...
                    }:
                      if inputs ? home-manager
                      then {
                        imports = import "${modulesPath}/modules.nix" {
                          inherit pkgs lib;
                          useNixpkgsModule = !(config.home-manager.useGlobalPkgs or false);
                        };

                        config = {
                          submoduleSupport.enable = true;
                          submoduleSupport.externalPackageInstall = config.home-manager.useUserPackages;

                          nix.package = config.nix.package;
                          home.username = config.users.users.${name}.name;
                          home.homeDirectory = config.users.users.${name}.home;
                        };
                      }
                      else {})
                  ]
                  ++ (config.home-manager.sharedModules or []);
              };
            };
          };
        };
      }));
    };
  };

  config = {
    users.users = foldl create-system-users {} user-names;
  };
}
