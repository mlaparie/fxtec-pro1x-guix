const version = (navigator.userAgent.match(/rv:(\d+)/) || [, "140"])[1];
const mobile = `Mozilla/5.0 (Android 14; Mobile; rv:${version}.0) Gecko/${version}.0 Firefox/${version}.0`;
browser.webRequest.onBeforeSendHeaders.addListener(async (details) => {
  const win = await browser.windows.getLastFocused();
  if (win.height <= win.width) return {};
  for (const header of details.requestHeaders) {
    if (header.name.toLowerCase() === "user-agent") header.value = mobile;
  }
  return { requestHeaders: details.requestHeaders };
}, { urls: ["<all_urls>"] }, ["blocking", "requestHeaders"]);
