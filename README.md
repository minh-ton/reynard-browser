# Reynard Browser

Reynard is a simple **Gecko-based** web browser for iOS 15+.

I still use devices that can’t be updated beyond iOS 15. On these versions, a lot of modern websites simply don’t work in Safari.

The core issue is **WebKit**, the browser engine behind Safari. It’s bundled with the OS, so if your device is stuck on an older iOS version, you’re stuck with an outdated browser. Although Apple now allows custom browser engines through the [BrowserEngineKit](https://developer.apple.com/documentation/browserenginekit) framework, this only applies to **iOS 17.4+** and only for users in the **EU** and **Japan**. There’s also the [CyberKit](https://github.com/CyberKitGroup/CyberKit) project, which attempts to backport WebKit, but its current releases are far from usable.

With Reynard, my goal is to build a Gecko-based browser that does not depend on BrowserEngineKit, allowing it to run on older iOS and iPadOS versions.

## Preview

<table>
  <tr>
    <td align="left">
      <img width=580 src="https://github.com/user-attachments/assets/03413002-be62-43ad-b648-4ef9367d3305"><br>
      Here's Reynard running on iPadOS 15...
    </td>
    <td align="left">
      <img width=200 src="https://github.com/user-attachments/assets/6c2ddfd8-ba2f-492c-975d-37d545bee02f"><br>
      …and on iOS 26
    </td>
  </tr>
</table>

## Issues
- The JIT backend for child processes is disabled, which means that the JS interpreter, JIT compiler, and WebAssembly are currently not available.
- Some POST request responses like dynamically loaded scripts and video streams are not fully delivered, which can cause Google reCAPTCHA to fail during loading or lead to stalled playback on YouTube. A workaround would be to set the user-agent string to a generic Firefox on Android one. I observed this behavior through debug logs and never fully understood it.
- On some websites that use `-apple-system`, `system-ui`, or `BlinkMacSystemFont`, the rendered text falls back to an overly thin SF UI variant.

## Changes
As of February 23, the browser uses a multi-process architecture, spawning child-processes (WebContent, Rendering, and Networking) through NSExtension. Most modern websites render correctly, including proper font and emoji support, and general browsing feels much smoother. While performance still does not match Safari, the browser is now reliable enough for everyday use.

<details>
<summary>Changes on February 4, 2026</summary>
As of Feb 4th 2026, the browser uses a single-process architecture, which is the simplest way I found to get Gecko up and running. It's slow and laggy in terms of performance. Most webpages render correctly, but fonts fall back to the system default, and the browser can crash on sites with popup or redirect ads.
</details>

## Build

Clone the repository.

```bash
git clone --recursive https://github.com/minh-ton/reynard-browser
cd reynard-browser
```

Download Gecko and apply patches.

```bash
./tools/development/update-gecko.sh
./tools/development/apply-patches.sh
```

Build the Gecko engine.

```bash
./tools/development/build-gecko.sh
```

To run Reynard, open `Reynard.xcodeproj` in Xcode and build/run it from there.

## Notes

If you’ve come across this repository and find it interesting, I’d love to get help or collaborate on it. I’m learning as I go here and don’t have much prior experience with iOS app development or with Gecko itself, so any contributions, feedback, or pointers would be greatly appreciated.

## License

This project is licensed under the MIT License, except for the `patches` directory containing the modifications to the Firefox Gecko engine and therefore is licensed under the Mozilla Public License 2.0.
