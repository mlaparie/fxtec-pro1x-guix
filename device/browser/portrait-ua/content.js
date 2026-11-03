if (screen.height > screen.width) {
  const version = (navigator.userAgent.match(/rv:(\d+)/) || [, "140"])[1];
  const values = {
    userAgent: `Mozilla/5.0 (Android 14; Mobile; rv:${version}.0) Gecko/${version}.0 Firefox/${version}.0`,
    appVersion: "5.0 (Android 14)",
    platform: "Linux armv81",
  };
  const page = window.wrappedJSObject.navigator;
  for (const [key, value] of Object.entries(values)) {
    Object.defineProperty(page, key, { get: exportFunction(() => value, window), configurable: true });
  }
}
