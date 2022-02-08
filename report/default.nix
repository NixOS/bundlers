# MIT License, see below
#
# These are some helpers for figuring out the derivations attributes of runtime
# dependencies of a derivation, in particular the function `runtimeReport`. At
# the bottom of the file you can see it used on `hello`. Spoiler: glibc is a
# runtime dependency.
# For more info see
#
#   https://nmattia.com/posts/2019-10-08-runtime-dependencies.html

# Let's call these "imports". They're functions used throughout the code.
# Nothing interesting here.
{ drv, pkgs ? import <nixpkgs>{}}:
with rec
  {
    inherit (pkgs)
      closureInfo
      runCommand
      writeText
      jq
      ;
    inherit (pkgs.lib)
      concatLists
      concatMap
      concatStringsSep
      filter
      isAttrs
      isDerivation
      isList
      isString
      mapAttrsToList
      ;
    inherit (builtins)
      genericClosure
      hasAttr
      toJSON
      typeOf
      unsafeDiscardStringContext
      ;
  };

let

# Create a "runtime report" of the runtime dependencies of `drv`. A "runtime
# report" is made up of smaller "dependency reports". A "dependency report" is
# a string describing the dependency, made from the dependency's derivation
# attributes. Here we use `mkReport` to make the report of any particular
# dependency.
#
# NOTE: we use the following terms:
#
#   * "buildtime" to mean basically any derivation involved in the build of
#     `drv`.
#   * "buildtime-only" for the "buildtime" dependencies that _are not_
#     referenced anymore by `drv`'s store entry.
#   * "runtime" for the rest.
#
# The "runtime report" is created in two steps:
#
#   * Generate reports for all the _buildtime_ dependencies with
#     `buildtimeReports`.
#   * Filter out the reports for buildtime-only dependencies.
#
# Most of the "buildtime" reports won't even be used, because most buildtime
# dependencies are buildtime-only dependencies. However Nix does not give us a
# way of retrieving the derivation attributes of runtime dependencies, but we
# can twist its arm to:
#
#   * Give us the store paths of runtime dependencies (see `cinfo`).
#   * Give us the derivation attributes of all the buildtime dependencies (see
#     `buildtimeDerivations`).
#
# Here's the hack: `buildtimeReports` tags the reports with the (expected)
# store path of the "buildtime" dependency, which we cross check against the
# list of runtime store paths. If it's a match, we keep it. Otherwise, we
# discard it.
runtimeReport = drv:
  runCommand "${drv.name}-report" { buildInputs = [ jq ]; }
  # XXX: This is to avoid IFD
  ''
    (
      echo "  ---------------------------------"
      echo "  |        OFFICIAL REPORT        |"
      echo "  |   requested by: the lawyers   |"
      echo "  |    written by: yours truly    |"
      echo "  |    TOP SECRET - TOP SECRET    |"
      echo "  ---------------------------------"
      echo
      echo "runtime dependencies of ${drv.name}:"
      cat ${buildtimeReports drv} |\
        jq -r --slurpfile runtime ${cinfo drv} \
          ' # First, we strip away (path-)duplicates.
            unique_by(.path)
            # Then we map over each build-time derivation and use `select()`
            # to keep only the ones that show up in $runtime

          | map(    # this little beauty checks if "obj.path" is in "runtime"
                select(. as $obj | $runtime | any(.[] | . == $obj.path))
              | .report)
          | .[]'
    ) > $out
  '';

# Creates reports for all of `drv`'s buildtime dependencies. Each element in
# the list has two fields:
#
#   * path = "/nix/store/..."
#   * report = "some report based on the dependency's derivation attributes"
buildtimeReports = drv: writeText "${drv.name}-runtime" ( toJSON (
  map (obj:
    # unsafe: optimization to avoid downloading unused deps
    { # XXX: we discard the context of the dependencies' store paths because
      # they're only ever used for lookup. This matters when fetching a
      # prebuilt final report -- there's no point downloading all of `drv`'s
      # buildtime dependencies.
      path = unsafeDiscardStringContext obj.key;
      report = mkReport obj.drv;
    }
  )
  (buildtimeDerivations drv) # the heavy lifting is done somewhere else
  ));

# Returns a list of all of `drv0`'s inputs, a.k.a. buildtime dependencies.
# Elements in the list has two fields:
#
#  * key: the store path of the input.
#  * drv: the actual derivation object.
#
# There are no guarantees that this will find _all_ inputs, but it works well
# enough in practice.
#
buildtimeDerivations = drv0:
  let
    # We include all the outputs because they each have different outPaths
    drvOutputs = drv:
      # XXX: some derivations, like stdenv, don't have "outputs"
      if hasAttr "outputs" drv
      then map (output: drv.${output}) drv.outputs
      else [ drv ];

    # Recurse into the derivation attributes to find new derivations
    drvDeps = attrs:
        mapAttrsToList (k: v:
        if isDerivation v then (drvOutputs v)
        else if isList v
          then concatMap drvOutputs (filter isDerivation v)
        else []
        ) attrs;
  in
    # Walk through the whole DAG of dependencies, using the `outPath` as an
    # index for the elements.
    let wrap = drv: { key = drv.outPath ; inherit drv; }; in genericClosure
    { startSet = map wrap (drvOutputs drv0) ;
      operator = obj: map wrap
        ( concatLists (drvDeps obj.drv.drvAttrs) ) ;
    };

# make a report. Would could also output a json object and process everything
# later on.
mkReport = drv:
  let
    license =
      if hasAttr "meta" drv && hasAttr "license" drv.meta then
        if isList drv.meta.license then
          concatStringsSep ", " (
            map renderLicense drv.meta.license)
        else renderLicense drv.meta.license
      else "no license";

    maintainer =
      if hasAttr "meta" drv && hasAttr "maintainers" drv.meta
      then concatStringsSep ", " (map (m: m.name) drv.meta.maintainers)
      else "nobody";

  in " - ${drv.name} (${license}) maintained by ${maintainer}";

# Basically pretty prints a license
renderLicense = license:
  if isAttrs license then license.shortName
  else if isString license then license
  else abort "no idea how to handle license of type ${typeOf license}";

# This is a wrapper around nixpkgs' `closureInfo`. It produces a JSON file
# containing a list of the store paths of `drv`'s runtime dependencies.
cinfo = drv: runCommand "${drv.name}-cinfo"
  { buildInputs = [ jq ]; }
  # NOTE: we avoid IFD here as well
  ''
    cat ${closureInfo { rootPaths = [ drv ]; }}/store-paths |\
      grep -v "^$" |\
      jq -R -s -c 'split("\n")' |\
      jq -c 'map(select( length > 0 ))' > $out
  '';

in {
  runtimeReport = runtimeReport drv;
  buildtimeDerivations = runCommand "${drv.name}-build" {
    big = builtins.toJSON (buildtimeDerivations drv);
    passAsFile = ["big"];
    buildInputs = [ pkgs.jq];
    } ''
      cp $bigPath $out
    '';
  # let result = buildtimeDerivations drv;
  #   in result;
}

# MIT License
#
# Copyright (c) 2021 Nicolas Mattia
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
