// electron-builder afterPack hook: drop SwiftShader (Chromium's software
// Vulkan fallback for WebGL) from the Electron Framework. Verse renders no
// WebGL, and on a real GPU Chromium never falls back to it, so it is dead
// weight (~16 MB installed).
//
// It then seals the whole bundle ad hoc. With `identity: null` electron-builder
// signs nothing, leaving only the linker's stub signature on the main binary
// with no sealed resources; macOS 27 rejects that bundle as "damaged".
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

exports.default = async function trimElectron(context) {
  if (context.electronPlatformName !== "darwin") return;
  const appName = context.packager.appInfo.productFilename;
  const app = path.join(context.appOutDir, `${appName}.app`);
  const framework = path.join(
    app,
    "Contents",
    "Frameworks",
    "Electron Framework.framework"
  );
  const libraries = path.join(framework, "Versions", "A", "Libraries");
  for (const name of ["libvk_swiftshader.dylib", "vk_swiftshader_icd.json"]) {
    const target = path.join(libraries, name);
    if (fs.existsSync(target)) {
      fs.rmSync(target);
    }
  }
  execFileSync("codesign", ["--force", "--deep", "--sign", "-", app]);
};
