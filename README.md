# A Based Open Source WiFi Aquarium LED DIY Kit

![Firmware Build Status](https://github.com/borneo-iot/borneo/actions/workflows/fw-ci.yml/badge.svg)
![App Build Status](https://github.com/borneo-iot/borneo/actions/workflows/flutter-ci.yml/badge.svg)

![BorneoIoT Banner](assets/borneo-repo-banner.jpg)

<p align="center">
    <a href="https://www.borneoiot.com"><b>Website</b></a> •
    <a href="https://docs.borneoiot.com"><b>Documentation</b></a> •
    <a href="https://github.com/borneo-iot/borneo/discussions"><b>Forum</b></a> •
    <a href="https://discord.gg/EFJTm7PpEs"><b>Discord</b></a>
</p>


---

The Borneo-IoT Project offers cutting-edge, open-source, modular, and affordable hardware and software solutions for hobbyists and professionals to create aquarium LEDs and other smart aquarium devices.


For more information, please visit the project's website: **[www.borneoiot.com](https://www.borneoiot.com)**.

PDF versions of the hardware schematics and datasheets [`hw/datasheets`](hw/datasheets).

**The project's PCB design uses [Horizon EDA](https://horizon-eda.org). After installation, you can open the `.hprj` file and export the BoM and Gerber files yourself.**

If you like this project, please don't forget to give it a ⭐. Thank you!

The Buce (Model BLC06MK1) LED controller in this project is an [OSHWA (Open Source Hardware Association)](https://www.oshwa.org) certificated open-hardware:

[![BLC06MK1](assets/buce-oshwa.png)](https://certification.oshwa.org/cn000017.html)

## Features

- **Full Stack Open Source**
    - PCB design (schematic and board layout) using [Horizon EDA](https://horizon-eda.org)
    - Firmware based on [ESP-IDF](https://idf.espressif.com/) framework
    - Flutter mobile app

- **Modular Hardware Design**
    - Compact core board (22×30mm) for easy integration
    - Reference schematics for custom PCB implementations

- **Component-based Firmware**
    - Multi-ESP32 family support (ESP32/ESP32-C3/C5) via unified board definitions
    - Zephyr RTOS-like driver architecture with hardware abstraction
    - CoAP + CBOR protocol stack for multi-device support (lamps, pumps, sensors)

- **Rich Functionality**
    - 6-channel PWM dimmer with zero peripheral components
    - Graphical sunrise/sunset dimming with soft-start
    - SNTP time sync & PID-controlled cooling sub-system
    - Python API client & demo scripts
    - Optional INA139 current monitoring

- **Cost-effective Solution**
    - ESP32-C3/ESP32 MCUs with standard components
    - Integrated driver for basic/PWM cooling fans
    - Pin-header friendly for DIY integration

- **Production-ready System**[^1]
    - Wireless OTA firmware updates
    - Automated production tools:
        - Batch programming & QA testing
        - Product parameter configuration

- **Field-proven**
    - The prototype of this dimmer and LED driver has been running stably on my own planted tank for years
    - Extensible architecture (ongoing pump/pH monitor development)

[^1]: The open-source project does not provide mass production-related fixtures and software.

## Demo Pictures & Videos

### Demo Short Video:

[![YouTube](http://i.ytimg.com/vi/Z78nOzLQvq0/hqdefault.jpg)](https://www.youtube.com/watch?v=Z78nOzLQvq0)

## Project Status

### Hardware & Firmware

**Beta**：The firmware is full functionality and stability, but some minor features are still not quite perfect.

### Mobile App

**Pre-Beta**：All major functions have been completed and are operational, but minor functions such as setting the time zone still need to be implemented, and the stability also requires further polishing.

## Roadmap

Checkout the [milestones](https://github.com/borneo-iot/borneo/milestones) to get a glimpse of the upcoming features and milestones.

## Directory Structure

- `client/`: Mobile app source code
- `borneopy/`: A open-source Python client library for the devices under the Borneo-IoT Project
- `fw/`: Firmware source code
    - `scripts`: Related Python scripts
    - `cmake`: CMake scripts
    - `components`: Common ESP-IDF component source code
    - `lyfi`: LED dimmer firmware-related source code
    - `doser`: Dosing pump firmware-related source code (under development)
- `hw/`: Circuit design source files
    - `blc06`: The board design of Buce, the 6-channel WiFi LED PWM dimmer
    - `blb0657f`: 6-channel 57W LED lamp aluminum PCB design
    - `bld6f`: 6-channel LED driver PCB design
    - `blc05mk3`: 5-channel LED driver PCB design (*Obsoleted*)
    - `blb08103`: 5-channel 63W LED lamp aluminum PCB design (*Obsoleted*)
    - `3d-models`: STEP format 3D models
    - `datasheets`: The hardware specifications in PDF format[^3]
- `tools/`: Related scripts and tools

[^3]: Since the datasheets are based on templates from my other products, the source file will not be provided in this repository.

## Getting Started

Please check out the [online documentation](https://docs.borneoiot.com/getting-started).

## Contribution

Please read [CONTRIBUTING.md](.github/CONTRIBUTING.md) for more details.

If you want to support the development of this project, you could consider buying me a beer.

<a href='https://ko-fi.com/O5O2U4W4E' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

[![Support via PayPal.me](assets/paypal_button.svg)](https://www.paypal.me/oldrev)

## Issues, Feedback & Support

We welcome your feedback! If you encounter any issues or have suggestions, please open an [issue](https://github.com/borneo-iot/borneo/issues).

- Website：[www.borneoiot.com](https://www.borneoiot.com)
- Online documentation：[docs.borneoiot.com](https://docs.borneoiot.com)
- GutHub Discussions: [github.com/borneo-iot/borneo/discussions](https://github.com/borneo-iot/borneo/discussions)
- Author's e-mail: [oldrev@gmail.com](mailto:oldrev@gmail.com)
- Borneo-IoT Discord Server: [discord.gg/EFJTm7PpEs](https://discord.gg/EFJTm7PpEs)

## License


### Software & Firmware

The software and firmware in this project is dual-licensed under the GNU General Public License version 3 or later (GPL-3.0+) and a proprietary license. You can find the full text of the GPL-3.0 license in the [LICENSE](LICENSE) file.

### Hardware

The hardware design in this project is licensed under the CERN Open Hardware Licence Version 2 - Strongly Reciprocal (CERN-OHL-S-2.0). You can find the full text of the license in the [LICENSE-HARDWARE](LICENSE-HARDWARE) file.

#### Proprietary Licensing

In addition to the GPL-3.0 license, I also offer proprietary licensing options for those who wish to use this software in proprietary products.

If you are interested in obtaining a proprietary license, please contact me at [oldrev@gmail.com](mailto:oldrev@gmail.com).

