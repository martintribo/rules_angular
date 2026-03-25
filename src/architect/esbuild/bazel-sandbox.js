/**
 * esbuild plugin for Bazel sandbox compatibility.
 *
 * esbuild is a Go binary that does its own filesystem operations,
 * bypassing Node's patched fs module. When running in Bazel's sandbox,
 * esbuild follows symlinks outside the sandbox. This plugin intercepts
 * resolved paths and remaps them back into the execroot.
 *
 * Based on rules_esbuild's bazel-sandbox plugin:
 * https://github.com/aspect-build/rules_esbuild/blob/main/esbuild/private/plugins/bazel-sandbox.js
 */
const path = require('path');

const bindir = process.env.BAZEL_BINDIR;
const execroot = process.env.JS_BINARY__EXECROOT;

module.exports = {
  name: 'bazel-sandbox',
  setup(build) {
    if (!execroot) return;

    build.onResolve({ filter: /./ }, async ({ path: importPath, ...opts }) => {
      if (opts.pluginData?.executedSandboxPlugin) return;
      opts.pluginData = { ...opts.pluginData, executedSandboxPlugin: true };

      const result = await build.resolve(importPath, opts);
      if (result.errors?.length || result.external) return result;
      if (!result.path.startsWith('/')) return result;

      if (!result.path.startsWith(execroot)) {
        if (bindir && result.path.includes(bindir)) {
          result.path = path.join(
            execroot,
            result.path.substring(result.path.indexOf(bindir))
          );
        }
      }
      return result;
    });
  },
};
