import assert from "node:assert/strict";
import vm from "node:vm";

const moduleURL = new URL(
  "../../.build/firefox/mobile/shared/components/extensions/FullPageCaptureCompat.sys.mjs",
  import.meta.url
);
const { FullPageCaptureCompat } = await import(moduleURL);

assert.equal(
  FullPageCaptureCompat.matchesExtension({ id: "another-extension", version: "1" }),
  false
);
assert.equal(
  FullPageCaptureCompat.matchesExtension({
    id: FullPageCaptureCompat.EXTENSION_ID,
    version: FullPageCaptureCompat.SUPPORTED_VERSION,
  }),
  true
);
assert.throws(
  () =>
    FullPageCaptureCompat.matchesExtension({
      id: FullPageCaptureCompat.EXTENSION_ID,
      version: "0.6.0",
    }),
  /unsupported/
);

const geometry = FullPageCaptureCompat.calculateCaptureGeometry(10_000, 10_000, 3);
assert.ok(geometry.scale < 1);
assert.ok(
  geometry.width * geometry.height <=
    FullPageCaptureCompat.CAPTURE_LIMITS.maximumPixels
);
assert.throws(
  () => FullPageCaptureCompat.calculateCaptureGeometry(1_000, 200_000, 3),
  /too large/
);
assert.throws(
  () => FullPageCaptureCompat.calculateCaptureGeometry(0, 100, 1),
  /invalid capture dimensions/
);

let injectedCode;
const extensionContext = {
  extension: { id: FullPageCaptureCompat.EXTENSION_ID },
};
await FullPageCaptureCompat.didExecuteScript(
  {
    async executeScript(_context, details) {
      injectedCode = details.code;
    },
  },
  extensionContext,
  { file: "/content/capture.js" },
  {
    async sendRequestForResult() {
      return {};
    },
  }
);
assert.ok(injectedCode.includes("maximumPixels"));
assert.ok(injectedCode.includes('"capture":"Capture"'));

await FullPageCaptureCompat.didExecuteScript(
  {
    async executeScript(_context, details) {
      injectedCode = details.code;
    },
  },
  extensionContext,
  { file: "/content/capture.js" },
  {
    async sendRequestForResult() {
      return { capture: "Take Screenshot" };
    },
  }
);
assert.ok(injectedCode.includes('"capture":"Take Screenshot"'));

const compatibilityMessages = [];
const compatibilityDispatcher = {
  async sendRequestForResult(type, message) {
    compatibilityMessages.push({ type, message });
    return {};
  },
};
assert.equal(
  await FullPageCaptureCompat.beforeDownload(
    extensionContext.extension,
    { filename: "ordinary.png" },
    compatibilityDispatcher
  ),
  null
);
assert.equal(
  await FullPageCaptureCompat.beforeDownload(
    extensionContext.extension,
    { filename: FullPageCaptureCompat.STAGED_FILES.beginRegionSelection },
    compatibilityDispatcher
  ),
  0
);
assert.equal(
  await FullPageCaptureCompat.handleStagedDownload(
    extensionContext.extension,
    { filename: FullPageCaptureCompat.STAGED_FILES.clipboardImage },
    compatibilityDispatcher
  ),
  0
);
assert.deepEqual(
  compatibilityMessages.map(message => message.type),
  [
    FullPageCaptureCompat.NATIVE_MESSAGES.beginRegionSelection,
    FullPageCaptureCompat.NATIVE_MESSAGES.clipboardImage,
  ]
);

function createFixture({ failAtTile = 0, youtube = false } = {}) {
  const scrolls = [];
  const canvases = [];
  const drawCalls = [];
  let captureCount = 0;
  let hideCount = 0;
  let restoreCount = 0;

  const context2D = {
    scale() {},
    drawImage(...arguments_) {
      drawCalls.push(arguments_);
    },
  };
  const inlineStyles = new Map([
    ["visibility", { value: "visible", priority: "" }],
    ["opacity", { value: "0.8", priority: "" }],
  ]);
  const bottomNavigation = {
    parentElement: null,
    style: {
      getPropertyPriority(property) {
        return inlineStyles.get(property)?.priority ?? "";
      },
      getPropertyValue(property) {
        return inlineStyles.get(property)?.value ?? "";
      },
      removeProperty(property) {
        inlineStyles.delete(property);
      },
      setProperty(property, value, priority = "") {
        inlineStyles.set(property, { value, priority });
      },
    },
    getBoundingClientRect() {
      return { left: 0, top: 70, right: 100, bottom: 100, width: 100, height: 30 };
    },
  };
  const document = {
    body: {},
    createElement(tagName) {
      assert.equal(tagName, "canvas");
      const canvas = {
        width: 0,
        height: 0,
        getContext(kind) {
          assert.equal(kind, "2d");
          return context2D;
        },
      };
      canvases.push(canvas);
      return canvas;
    },
    elementsFromPoint() {
      return youtube ? [bottomNavigation] : [];
    },
    querySelectorAll() {
      return youtube ? [bottomNavigation] : [];
    },
  };
  bottomNavigation.parentElement = document.body;
  const fpc = {
    outputResult: async () => {},
    blobToDataUrl: async () => "data:image/png;base64,AA==",
    sleep: async () => {},
    getPageDimensions() {
      return {
        fullWidth: 100,
        fullHeight: 250,
        viewportWidth: 100,
        viewportHeight: 100,
        scrollX: 7,
        scrollY: 11,
      };
    },
    getScrollViewportRect() {
      return { left: 0, top: 0 };
    },
    captureViewport: async () => "viewport",
    scroll(x, y) {
      scrolls.push([x, y]);
    },
    awaitScroll: async () => {},
    findFixedElements() {
      return [{ selector: "#fixed" }];
    },
    waitForCaptureReady: async () => {},
    loadImage: async () => ({ naturalWidth: 100, naturalHeight: 100 }),
    hideFixed() {
      hideCount += 1;
    },
    restoreFixed() {
      restoreCount += 1;
    },
    canvasToPngBlob: async () => ({ type: "image/png" }),
  };
  const window = {
    FullPageCapture: fpc,
    devicePixelRatio: 2,
    innerWidth: 100,
    innerHeight: 100,
    scrollX: 0,
    scrollY: 0,
    addEventListener() {},
    removeEventListener() {},
  };
  const sandbox = {
    Blob,
    browser: {
      runtime: {
        async sendMessage() {
          captureCount += 1;
          if (failAtTile && captureCount === failAtTile) {
            throw new Error("forced tile failure");
          }
          return { success: true, dataUrl: "data:image/png;base64,AA==" };
        },
      },
    },
    clearInterval,
    clearTimeout,
    document,
    fetch,
    getComputedStyle() {
      return { position: "fixed" };
    },
    location: { hostname: youtube ? "m.youtube.com" : "example.com" },
    performance,
    requestAnimationFrame(callback) {
      return setTimeout(callback, 0);
    },
    cancelAnimationFrame: clearTimeout,
    setInterval,
    setTimeout,
    window,
  };
  vm.runInNewContext(injectedCode, sandbox);
  return {
    canvases,
    drawCalls,
    fpc,
    inlineStyles,
    scrolls,
    get hideCount() {
      return hideCount;
    },
    get restoreCount() {
      return restoreCount;
    },
  };
}

const successFixture = createFixture();
const result = await successFixture.fpc.captureFullPage(1);
assert.equal(result.type, "image/png");
assert.equal(successFixture.drawCalls.length, 3);
assert.equal(successFixture.hideCount, 1);
assert.equal(successFixture.restoreCount, 1);
assert.deepEqual(successFixture.scrolls.at(-1), [7, 11]);
assert.equal(successFixture.canvases[0].width, 1);
assert.equal(successFixture.canvases[0].height, 1);

const failureFixture = createFixture({ failAtTile: 2 });
await assert.rejects(
  failureFixture.fpc.captureFullPage(1),
  /forced tile failure/
);
assert.equal(failureFixture.hideCount, 1);
assert.equal(failureFixture.restoreCount, 1);
assert.deepEqual(failureFixture.scrolls.at(-1), [7, 11]);
assert.equal(failureFixture.canvases[0].width, 1);
assert.equal(failureFixture.canvases[0].height, 1);

const youtubeFixture = createFixture({ youtube: true });
await youtubeFixture.fpc.captureFullPage(1);
assert.equal(youtubeFixture.drawCalls.length, 4);
assert.equal(youtubeFixture.drawCalls.at(-1)[6], 220);
assert.equal(youtubeFixture.inlineStyles.get("visibility").value, "visible");
assert.equal(youtubeFixture.inlineStyles.get("opacity").value, "0.8");

console.log("FullPageCaptureCompatTests passed");
