<img width="100" height="100" src="https://github.com/user-attachments/assets/1c42dda2-b778-4342-9f94-8f852c3ad652" />

# Reynard Browser

Reynard is a **Gecko-based** mobile web browser for iOS 14+.

Unlike other browsers on iOS that are forced to use Apple's **WebKit** engine (including Safari and all third-party browsers), Reynard uses **Gecko**. This is the same engine that powers the Firefox browser on desktop and Android devices.

This project is mainly for users on older iOS versions who are stuck with an outdated version of WebKit. Because WebKit is bundled with the OS, these devices cannot receive engine updates and often fail to load modern websites. By using Gecko which is kept up to date independently, Reynard allows these sites to work again. Users on newer iOS versions can also use the browser if they want an alternative browser engine on their device.

## Installation

The latest builds are available on the [Releases](https://github.com/minh-ton/reynard-browser/releases) page.

For the best performance and automatic JIT enablement, it is recommended to sideload Reynard via [TrollStore](https://github.com/opa334/TrollStore) using the `Reynard-TrollStore.tipa` build.

If TrollStore is not available, you should use [AltStore](https://altstore.io/) or [SideStore](https://sidestore.io/) to sideload the `Reynard.ipa` build instead. Please note that you must select the **Keep App Extensions** option during installation, as Reynard relies on its extensions to function and will not work without them. After sideloading, you may want to enable JIT by following [this guide](https://github.com/minh-ton/reynard-browser/wiki/2.-Enabling-JIT).

You can also [click here](https://stikstore.app/altdirect/?url=https://github.com/minh-ton/reynard-browser/releases/download/0.0.1-a1/source.json&exclude=livecontainer) to add the AltStore Source for Reynard in AltStore or SideStore.

> [!WARNING]
> - **LiveContainer is not supported**, as it does not support extensions or launch apps in a way that is compatible with Reynard.
> - Compatibility with other sideloading methods is currently unknown.

This project is still in an early experimental state, so expect bugs and missing features. If you encounter issues, check the [Issues & FAQ](https://github.com/minh-ton/reynard-browser/wiki/3.-Issues-&-FAQ) page before opening a new issue.

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
      <img width=150 src="https://github.com/user-attachments/assets/917ee435-39cb-469d-835f-8e69f9e13d03"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/1a68024e-83d4-489c-a576-26d5ea43011c"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/6880b1ac-63f9-421f-a373-5d69c5745cd7"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/d237118e-be3b-43d1-b14c-032784b43571"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/9f799569-d712-44d0-918a-21d523874c6e"><br>
    </td>
  </tr>
</table>

### iOS 15 (iPhone 7, 15.8.6)

<table>
  <tr>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/a7f1b302-51b6-4afe-a2ce-35b518e5b761"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/f5dbfba5-c1a8-4729-bd7d-b96a7ace1237"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/986c8cfb-7979-4f4b-9305-73ebd1a87b19"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/544ff493-6807-4b2f-b526-6d34f029e1d3"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/31ef9486-8631-4d0e-ad9a-1281d513151f"><br>
    </td>
  </tr>
</table>

### iOS 26 (iPhone 13 mini, 26.1)

Reynard also works great on the latest version of iOS!

<table>
  <tr>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/974e8ce1-f798-4bef-bac1-621ee535c5ee"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/1429c985-f439-4e58-9385-0eefef4add4c"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/a9eeaf68-828f-4ead-b619-8b9914e0ed2c"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/bbc08422-4bf3-4928-933e-71cdad551fed"><br>
    </td>
    <td>
      <img width=150 src="https://github.com/user-attachments/assets/cf01d298-a8d2-49ea-a557-7b1bbd1d893a"><br>
    </td>
  </tr>
</table>

## Building

> [!WARNING]
> Build instructions are included below for reference. Please be aware that I **do not** provide support for issues or errors encountered during the build process.

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

## Notes

This project initially started out of curiosity. I wanted to see if I could get Gecko to run without the [BrowserEngineKit](https://developer.apple.com/documentation/browserenginekit) framework, so it could be further modified to run on iOS versions as far back as possible. I got it working, and since then, I’ve been focusing on developing engine patches for better UIKit integration, fixing bugs, and turning this into a full, usable browser.

If you’ve come across this repository and find it interesting, I’d love to get help or collaborate on it. I’m learning as I go here and don’t have much prior experience with iOS app development or with Gecko itself, so any contributions, feedback, or pointers would be greatly appreciated.

## Acknowledgements
- [LiveContainer](https://github.com/LiveContainer/LiveContainer): app extension handling and NSExtension usage.
- [StikDebug](https://github.com/StephenDev0/StikDebug) and [idevice](https://github.com/jkcoxson/idevice): pairing-based JIT enablement support.
- [TrollStore](https://github.com/opa334/TrollStore): spawning a binary as root and JIT enablement.
- [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) and [dolphin-ios](https://github.com/OatmealDome/dolphin-ios): Various utility functions, numerous private API usage, and memory mapping stuff.
- [Pre-existing work](https://bugzilla.mozilla.org/show_bug.cgi?id=1882872) on bringing Gecko to iOS using BrowserEngineKit: most of the difficult engine integration. 

## License

This project is licensed under the MIT License, except for the `patches` directory containing the modifications to the Firefox Gecko engine and therefore is licensed under the Mozilla Public License 2.0.
