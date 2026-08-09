# Walkthrough PDFs

`generate_walkthroughs.swift` produces both printable guides:

- `output/pdf/whisper-bridge-android-walkthrough.pdf`
- `output/pdf/whisper-bridge-iphone-walkthrough.pdf`

Run it from the repository root with Xcode's Swift toolchain:

```bash
swiftc -O -framework AppKit -framework CoreText \
  -o /tmp/generate_walkthroughs \
  documentation/walkthrough/generate_walkthroughs.swift
/tmp/generate_walkthroughs
```

The iPhone guide uses the compact simulator captures in
`documentation/screenshots/ios-walkthrough-*.png`. Regenerate those captures
from the iPhone simulator when the iOS UI changes materially, then regenerate
the PDFs.
