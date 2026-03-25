"Macro definition to copy & modify root config files"

load("@jq.bzl//jq:jq.bzl", "jq")

# Strip tsconfig paths that point outside the project dir.
# In Bazel, workspace packages resolve through node_modules (set up by npm_link_all_packages),
# not tsconfig paths pointing to source files.
JQ_DIST_REPLACE_TSCONFIG = """
    .compilerOptions.paths |= if . then
      with_entries(select(.value | all(startswith("..") | not)))
      | if . == {} then null else . end
    else null end
    | .compilerOptions |= with_entries(select(.value != null))
"""

# Update angular.json for Bazel:
# - Redirect output paths to be local to the BUILD file
# - For esbuild application builders, swap to @angular-builders/custom-esbuild
#   and inject the bazel-sandbox plugin (esbuild is a Go binary that bypasses
#   Node's patched fs, so it needs a plugin to remap sandbox-escaping paths)
JQ_DIST_REPLACE_ANGULAR = """
(
  .projects | to_entries | map(
    if .value.projectType == "application" then
      .value.architect.build.options.outputPath = "./" + .value.root + "/dist"
      |
      if .value.architect.build.builder == "@angular/build:application" then
        .value.architect.build.builder = "@angular-builders/custom-esbuild:application"
        | .value.architect.build.options.plugins = ["./esbuild/bazel-sandbox.js"]
      else
        .
      end
    else
      .
    end
  ) | from_entries
) as $updated |
. * {projects: $updated}
"""

# buildifier: disable=function-docstring
def ng_config(name, **kwargs):
    jq(
        name = "angular",
        srcs = ["angular.json"],
        filter = JQ_DIST_REPLACE_ANGULAR,
    )

    # NOTE: project dist directories are under the project dir unlike the Angular CLI default of the root dist folder
    jq(
        name = "tsconfig",
        srcs = ["tsconfig.json"],
        filter = JQ_DIST_REPLACE_TSCONFIG,
    )

    # Copy the bazel-sandbox esbuild plugin so it's available in the sandbox
    native.genrule(
        name = "_esbuild_sandbox_plugin",
        srcs = [Label("//src/architect/esbuild:bazel-sandbox.js")],
        outs = ["esbuild/bazel-sandbox.js"],
        cmd = "cp $< $@",
    )

    native.filegroup(
        name = name,
        srcs = [":angular", ":tsconfig", ":_esbuild_sandbox_plugin"],
        **kwargs
    )
