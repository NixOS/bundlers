# Nix Bundlers

Bundlers are a way to transform derivations. The most common and default usage is based on the [original by matthewbauer](https://github.com/matthewbauer/nix-bundle). Each bundler is function over a value (usually a derivation) that produces another derivation.

```console
$ nix bundle --bundler github:NixOS/bundlers nixpkgs#hello
```

# How to contribute

Main purpose of this repository is to collect most common bundlers to *make
common use-cases easy*. For this purpose the collection of bundlers is limited
to provided an opinionated and curated list.

TODO: bundlers should be also discoverable on search.nixos.org

## Opening issues

* Make sure you have a [GitHub account](https://github.com/signup/free)
* Make sure there is no open issue on the topic
* [Submit a new issue](https://github.com/NixOS/templates/issues/new)


## What is required to submit a bundler?

Note: This section is a WIP

Each bundler needs:

- `name`

  Folder with the same name should be created and this is a location of the
  bundler. An entry with `name` is requred in `flake.nix`.

- `description`

  A description that explains the content of the bundler in one sentence. An
  entry with `description` is requred in `flake.nix`.

- `maintainers`

  Each bundler needs one of more maintainers with the knowledge of specific
  area. Each bundler has an entry in `.github/CODEOWNERS` with maintainers
  next to them.

# License

Note: contributing implies licensing those contributions
under the terms of [COPYING](COPYING), which is the MIT license.
