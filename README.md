DigiHub - Digital Hub for ham radio 
===================================
Overview
--------
DigiHub is not an application or environment; it is a curated collection of ham radio utilities and applications geared toward Digital ham radio Operations.

It is designed as an alternative to the popular DigiPi, which is an excellent implementation and is a highly recommended option for those setting out on the digital ham path.

DigiHub builds on the DigiPi concept and is designed to be installed on an existing Debian system rather than being a complete Operating System image.

The installation script has been built and tested on Debian trixie 64-bit, which includes Raspberry Pi OS running on a Pi Zero 2W, 3, 4, or 5.

The primary design goal of DigiHub is flexibility and configurability:

Digihub
|:---------------------------------------------------------------------------------------------------|
Validates (US) callsigns.
Has an editable configuration
Automatically calculates maidenhead grid square from Latitude and Longitude when using a GPS device.
Automatically generates the correct APRS password.
Automatically generates a random alphanumeric AX node password.
Can be installed for an individual or club callsign.
Can be installed on an existing Debian Linux trixie x64 Operating System.
Is completely free.

Command Line Utilties
---------------------
A number of the methods used to install, run and maintain DigiHub are included as command line utilities:

| Command     | Purpose                                                     | Written in  |
|:------------|:------------------------------------------------------------|:------------|
aprspass      | Generate an APRS password                                   | bash/python |
checkcall     | Check a US callsign using the hamdb API                     | bash        |
dwsetup       | Install, or update an existing installation of Direwolf     | bash        |
editconfig    | Edit the DigHub installation (callsign, grid etc.)          | bash        |
gpsposition   | Get current GPS position from GPS device                    | bash/python |
hamgrid       | Calculate a Maidenhead ham grid from latitude and longitude | bash/python |
sysinfo       | System information                                          | bash        |
uninstall     | Remove DigiHub                                              | bash        |
whohami       | Show user information held for current configuration        | bash        |

These along with other valuable tools are located in DigiHub/scripts (included in the PATH after install).

GPS Devices
-----------
DigiHub will detect and use correctly installed and working GPS devices.

A recommended GPS device is a Waveshare L76X Multi-GNSS HAT (available [here](https://www.waveshare.com/l76x-gps-hat.htm)). It works with any PC hardware via USB and with Raspberry Pi via the GPIO header.

Operators without a US callsign
-------------------------------
DigiHub leverages an API for callsign validation and user data, which is reliable in the US; unfortunately, outside the US, this is not the case.

To enable ham operators outside the US to use DigiHub, entering non-us (or NON-US) as the callsign when installing DigiHub, e.g., ./install.sh NON-US, allows manual entry of the unvalidated callsign and other required information.

Installation
-------------
Ensure the Operating System you are installing on has an active Internet connection and, if you intend to use a GPS, it is connected and working.

**Note:** *python3, wget and curl will be installed as part of the process if not already available and will NOT be removed if DigiHub is removed.*

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

| Source    | Link                                          | Purpose             |
|:----------|:----------------------------------------------|:--------------------|
| hamdb.org | https://hamdb.org                             | API Calls           |
| Direwolf  | https://github.com/wb2osz/direwolf            | Direwolf            |
| scripts   | https://github.com/dslotter/ham_radio_scripts | FLdigi Installation |
| DigiPi    | https://digipi.org                            | Concept & content   |






