# Portrait user agent

A WebExtension for the Firefox family: a mobile user agent while the window is
in portrait, the browser's own in landscape.  Pages such as DuckDuckGo then
send their mobile layout in portrait (author, 2026-11-03, LibreWolf 158, loaded
from about:debugging: the layout fits, and rotation is respected).

State: signed by Mozilla for self-distribution (unlisted, version 0.1), as
device/sway/pro1x-portrait-ua.xpi; pro1x-browser-fit puts it in each profile of
LibreWolf, IceCat and Firefox at login.  A change here needs a new version,
uploaded and signed with the owner's account, before it reaches the port.  A
page already loaded keeps its identity until reloaded.  In portrait the browser
stands out next to resistFingerprinting's uniform agent.
