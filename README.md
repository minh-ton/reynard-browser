<img width="100" height="100" src="https://github.com/user-attachments/assets/1c42dda2-b778-4342-9f94-8f852c3ad652" />

# Reynard Browser

Reynard is a **Gecko-based** web browser for iOS 13+.

Unlike other browsers on iOS that are forced to use Apple's **WebKit** engine (including Safari and all third-party browsers), Reynard uses **Gecko**. This is the same engine that powers the Firefox browser on desktop and Android devices.

Besides providing an **alternative, up-to-date browser engine**[^1], Reynard supports Firefox add-ons, including more capable ad-blocking extensions, along with privacy features such as Enhanced Tracking Protection and DNS over HTTPS.

[^1]: This is particularly useful on older iOS versions. Because WebKit is bundled with the OS, devices that no longer receive iOS updates are also stuck with an older browser engine, which can cause modern websites to break or render incorrectly.

## Installation

The latest builds are available for download on the [Releases](https://github.com/minh-ton/reynard-browser/releases) page. Please note that this project is still in beta, so expect bugs and missing features.

For common questions and troubleshooting, see the [FAQ](https://github.com/minh-ton/reynard-browser/issues/130).

Reynard is available as a standard build, a TrollStore build[^2], and a jailbroken build[^3], depending on your iOS version and installation method:

<table>
  <thead>
    <tr>
      <th>Method</th>
      <th>iOS version</th>
      <th>Build</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><a href="https://altstore.io/">AltStore</a> or <a href="https://sidestore.io/">SideStore</a></td>
      <td>iOS 17.4+</td>
      <td><a href="https://github.com/minh-ton/reynard-browser/releases/latest/download/Reynard.ipa"><code>Reynard.ipa</code></a></td>
    </tr>
    <tr>
      <td><a href="https://github.com/opa334/TrollStore">TrollStore</a></td>
      <td>iOS 14 - 16.6.1, 17.0</td>
      <td><a href="https://github.com/minh-ton/reynard-browser/releases/latest/download/Reynard-TrollStore.tipa"><code>Reynard-TrollStore.tipa</code></a></td>
    </tr>
    <tr>
      <td><a href="https://github.com/opa334/TrollStore">TrollStore</a></td>
      <td>Jailbroken iOS 14</td>
      <td><a href="https://github.com/minh-ton/reynard-browser/releases/latest/download/Reynard-Jailbroken.ipa"><code>Reynard-Jailbroken.ipa</code></a></td>
    </tr>
    <tr>
      <td><a href="https://havoc.app/package/trollstorelite">TrollStore Lite</a></td>
      <td>Jailbroken iOS 16.7 - 16.7.16, 17.0.1+</td>
      <td><a href="https://github.com/minh-ton/reynard-browser/releases/latest/download/Reynard-TrollStore.tipa"><code>Reynard-TrollStore.tipa</code></a></td>
    </tr>
    <tr>
      <td><a href="https://www.tigisoftware.com/default/?page_id=78">Filza File Manager</a> + <a href="https://github.com/akemin-dayo/AppSync">AppSync Unified</a></td>
      <td>Jailbroken iOS 13</td>
      <td><a href="https://github.com/minh-ton/reynard-browser/releases/latest/download/Reynard-Jailbroken.ipa"><code>Reynard-Jailbroken.ipa</code></a></td>
    </tr>
  </tbody>
</table>

[^2]: The TrollStore build provides automatic JIT enablement, better performance, and automatic app updates. For automatic app updates, make sure **URL Scheme Enabled** is turned on in TrollStore.
[^3]: The jailbroken build provides automatic JIT enablement and better performance. However, several components are switched off to provide compatibility with libhooker-based jailbreak environments. Automatic app updates is also available when installed through TrollStore.

> [!NOTE]
> Although jailbroken builds are available, using Reynard on a jailbroken device is not recommended. Tweaks and other system modifications may affect the browser's performance, stability, or functionality, and support for resulting issues may be limited. **On any jailbroken device**, disable tweak injection for Reynard and its extensions using tools such as [Choicy](https://github.com/opa334/Choicy).

**For AltStore or SideStore installations:**

Make sure to select **Keep App Extensions** during installation, as Reynard will not work without them.

You can also [click here](https://altdirect.app/?url=https://github.com/minh-ton/reynard-browser/releases/download/0.0.1-a1/source.json&exclude=livecontainer,stikstore,trollapps,feather) to add the AltSource for Reynard to AltStore or SideStore.

> [!IMPORTANT]
> - **LiveContainer is not supported** due to its own limitations.
> - Sideloading using a distribution certificate for signing is **not supported**.⁠
> - Other sideloading methods may be **incompatible with Reynard**, and **no support will be provided** for issues arising from them.

## Preview

### iOS 14 (iPhone 6S Plus, 14.1)

These sites are known to break or render incorrectly on iOS 14. The screenshots below compare how they load in Safari versus Reynard.

<table>
  <tr>
    <th colspan="2">github.com</th>
    <th colspan="2">chatgpt.com</th>
    <th colspan="2">apple.com</th>
  </tr>
  <tr>
    <td align="center">Safari</td>
    <td align="center">Reynard</td>
    <td align="center">Safari</td>
    <td align="center">Reynard</td>
    <td align="center">Safari</td>
    <td align="center">Reynard</td>
  </tr>
  <tr>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/d89f4385-c478-4aea-aa9d-6c9fca72252b"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/279f8268-b196-415d-9199-66c06989ae7f"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/1a68024e-83d4-489c-a576-26d5ea43011c"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/eb8f0073-04c2-436d-b66c-9ba2af8e56c2"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/0e52fbf1-af5d-4a83-9bba-50c5d1e15d57"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/edbd8e50-a02d-4107-a5e2-f8ab2c6382bb"><br>
    </td>
  </tr>
</table>

### iOS 15 (iPhone 7, 15.8.6)

<table>
  <tr>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/e716f563-8ab5-4d3c-b49a-4bb66fc78d59"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/33ece0a3-c876-40c5-acdc-26ea3ac9b9b6"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/96ed97e3-aa57-4b80-adee-108699fef90d"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/e9018214-53ef-41b2-a92c-ed03e7d2a366"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/abe83082-1fc6-4ee9-999e-f81e1712ac13"><br>
    </td>
  </tr>
</table>

### iOS 26 (iPhone 13 mini, 26.1)

Reynard also works great on the latest version of iOS!

<table>
  <tr>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/62568ad7-c84c-4623-a560-f679c2a47755"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/4c43cda8-5451-4876-9556-2529a36e0e62"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/d213427d-c207-4129-82b4-a19b091072e0"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/f0e7b590-63be-44cf-87c2-c790c59bd915"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/6015bbc0-727c-4fca-9756-3ec3d256f162"><br>
    </td>
  </tr>
</table>

## Building

> [!WARNING]
> Build instructions are included below for reference. Please be aware that I **do not** provide support for issues or errors encountered during the build process.

To build the project, you'll need Xcode, [Python 3](https://www.python.org/downloads/), and [Rust & Cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html).

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

Build dependencies and the Gecko engine.

```bash
./tools/development/build-idevice.sh
./tools/development/build-gecko.sh
```

To run Reynard, open `Reynard.xcodeproj` in Xcode and build/run it from there.

## Development

This project initially started out of curiosity. I wanted to see if I could get Gecko to run without the [BrowserEngineKit](https://developer.apple.com/documentation/browserenginekit) framework, so it could be further modified to support iOS versions as far back as possible. I got it working, and since then, I’ve been focusing on developing engine patches for better integration with iOS, fixing bugs, and turning Reynard into a full, usable browser.

If you’ve come across this repository and find it interesting, I’d love to get help or collaborate on it. I’m learning as I go here and don’t have much prior experience with iOS app development or with Gecko itself, so any contributions, feedback, or pointers would be greatly appreciated.

You can also help translate Reynard into more languages, or support the time I spend working on the project through the links below.

<a href="https://crowdin.com/project/reynard-browser"><img height="40" src="https://github.com/user-attachments/assets/5f00681e-c31a-4c7f-87fe-caaf67ee52d7" /></a>
<a href="https://buymeacoffee.com/hnimnot"><img height="40" src="https://github.com/user-attachments/assets/ea72836b-3d60-4ffc-be93-d62d5df51047" /></a>

## Acknowledgements
- [LiveContainer](https://github.com/LiveContainer/LiveContainer): app extension handling and NSExtension usage.
- [StikDebug](https://github.com/StephenDev0/StikDebug) and [idevice](https://github.com/jkcoxson/idevice): pairing-based JIT enablement support.
- [TrollStore](https://github.com/opa334/TrollStore): spawning a binary as root and JIT enablement.
- [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS), [dolphin-ios](https://github.com/OatmealDome/dolphin-ios), [DukeX](https://github.com/MaftyManicEMU/DukeX), and [MeloNX](https://git.ryujinx.app/projects/MeloNX): Various utility functions, numerous private API usage, and JIT memory handling.
- [WebKit](https://github.com/webkit/webkit): Private API references for deeper iOS integration, such as sandboxing, hardware keyboard support, and lifecycle events.
- [Pre-existing work](https://bugzilla.mozilla.org/show_bug.cgi?id=1882872) on bringing Gecko to iOS using BrowserEngineKit: most of the difficult engine integration. 

## License

This project is licensed under the [GNU General Public License v3.0](https://github.com/minh-ton/reynard-browser/blob/main/LICENSE), except for the `patches` directory containing the modifications to the Firefox Gecko engine and therefore is licensed under the [Mozilla Public License 2.0](https://github.com/minh-ton/reynard-browser/blob/main/LICENSE.firefox).
