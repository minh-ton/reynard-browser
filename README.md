# Reynard Browser

Reynard is a simple, bare-bones **Gecko-based** web browser for iOS 15+.

I still use devices that can’t be updated beyond iOS 15. On these versions, a lot of modern websites simply don’t work in Safari.

The core issue is **WebKit**, the browser engine behind Safari. It’s bundled with the OS, so getting a newer engine usually means updating the entire system. If your device is stuck on an older iOS version, you’re stuck with an outdated browser too.

It doesn’t help that although Apple now allows custom browser engines through the [BrowserEngineKit](https://developer.apple.com/documentation/browserenginekit) framework, this only applies to **iOS 17.4+** and only for users in the **EU**, thanks to the Digital Markets Act. There’s also the [CyberKit](https://github.com/CyberKitGroup/CyberKit) project, which attempts to backport WebKit, but its current releases are far from usable.

With Reynard, my goal is to build a Gecko-based browser that does not depend on BrowserEngineKit, allowing it to run on older iOS and iPadOS versions.

This repository contains the source code for the Reynard Browser itself. If you’re looking for the Gecko port, see my [truefox](https://github.com/minh-ton/truefox) repository.

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

As of Feb 4th 2026, the browser uses a single-process architecture, which is the simplest way I found to get Gecko up and running. It's slow and laggy in terms of performance. Most webpages render correctly, but fonts fall back to the system default, and the browser can crash on sites with popup or redirect ads.

## Building the Project

Clone the repository along with the `truefox` submodule.

```bash
git clone --recursive https://github.com/minh-ton/reynard-browser
cd reynard-browser
```

Inside the `truefox` folder, create a file named `.mozconfig` with the following contents. These are the build configuration.

```
ac_add_options --enable-application=mobile/ios
ac_add_options --target=aarch64-apple-ios
ac_add_options --enable-ios-target=15.0
ac_add_options --enable-optimize
ac_add_options --with-ccache=sccache
```

Build Gecko as usual.

```bash
cd truefox
./mach build
```

To run Reynard, open `Reynard.xcodeproj` in Xcode and build/run it from there.

## Notes

If you’ve come across this repository and find it interesting, I’d love to get help or collaborate on it. I’m learning as I go here and don’t have much prior experience with iOS app development or with Gecko itself, so any contributions, feedback, or pointers would be greatly appreciated.

## License

This project is licensed under the MIT License. The included [truefox](https://github.com/minh-ton/truefox) engine is licensed separately under MPL-2.0.
