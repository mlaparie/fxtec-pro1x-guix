# Portrait user agent

A WebExtension for the Firefox family: a mobile user agent while the window is
in portrait, the browser's own in landscape.  Pages such as DuckDuckGo then
send their mobile layout in portrait (author, 2026-11-03, LibreWolf 158, loaded
from about:debugging: the layout fits, and rotation is respected).

State: tested as a temporary add-on only, gone at each browser restart.  Not
installed by the port.  To install it for good it needs Mozilla's signature for
self-distribution (`web-ext sign --channel=unlisted`, with the owner's API keys,
which stay out of git); turning signature checks off is not the plan.  A page
already loaded keeps its identity until reloaded.  In portrait the browser
stands out next to resistFingerprinting's uniform agent.
