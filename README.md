DigiHub - Digital Hub for ham radio 
===================================
Overview
--------
DigiHub is not an application or environment, it is a curated collection of ham radio utilities and applications geared toward Digital ham radio Operations.
It is designed to be an alternative to the popular DigiPi which is an excellent implementation (but has limitations) and, is a highly recommended option for those setting out on the digital ham path.

DigiHub, builds on the DigiPi concept and is designed to be installed on an existing Debian system rather than being a complete Operating system image.

The installation script has been built and tested on Debian trixie 64-bit meaning it can be installed on Raspberry Pi OS running on a Pi Zero 2W, 3, 4 or, 5.

The primary design goal of DigiHub is flexibility and configurability:

Digihub
|:------------------------------------------------------------------------------------------------------|
Validates (US) callsigns.
Editable coinfiguration
Automatically calculates maidenhead grid square from Latitude and Longitude when using a GPS device.
Automatically generates the correct APRS password.
Automatically generates a random alphanumeric AX node password.
Can be installed for an individual or club callsign.
Is completely free.

Command Line Utilties
---------------------
A number of the methods used to install, run and maintain DigiHub are included as command line utilities:

| Command     | Purpose                                                     | Written in  |
|:------------|:------------------------------------------------------------|:------------|
aprspass      | Generate an APRS password                                   | bash/python |
checkcall     | Check a US callsign using the hamdb API                     | bash        |
dwsetup       | Install, or update an existing installation of Direwolf     | bash        |
editconfig    |                                                             |             |
gpsposition   |                                                             |             | 
hamgrid       | Calculate a Maidenhead ham grid from latitude and longitude | bash/python |
sysinfo       | System information                                          | bash        |
unistall      | Remove DigiHub                                              |             |
whohami       | Show user information held for current configuration        | bash        |

These along with other useful tools are located in DigiHub/scripts (included in the PATH after install).

GPS Devices
-----------
DigiHub will detect and use correctly installed and working GPS devices.

A recommended GPS device is a Waveshare L76X Multi-GNSS HAT (avaialble [here](https://www.waveshare.com/l76x-gps-hat.htm)), it works with any PC hardware via USB, and Raspberry Pi via the GPIO header.

Users without a US callsign
---------------------------
DigiHub leverages an API for callsigns and user data which in the US is reliable, unfortunately outside the US this is not the case. 
To enable users outside the US to use DigiHub, entering non-us (or NON-US) as the callsign when installing DigiHub (e.g. ./install.sh NON-US) allows manual entry of the unvalidated callsign and other required information.

Installation
-------------
Ensure the Operating System you are installing on has an active Internet connection and, if you intend to use a GPS, it is connected and working.

Note: python3, git (to cover the instacence of copying rather than downloading the repository),and curl will be installed as part of the process if not already available and wiil NOT be removed during uninstallation.

Issue the following commands:

If necessary, install git:
```bash
sudo apt install git
```
Change directory to the install folder, make the installer executable and run it:

```bash
git clone https://github.com/debods/DigiHubHam.git
cd DigiHubHam
chmod +x install.sh
./install.sh <callsign>
```
All software installed by DigiHub is open-source licensed and freely available.

Credits
-------
DigiPi    https://digipi.org
Direwolf  https://github.com/wb2osz/direwolf
hamdb     https://hamdb.org






