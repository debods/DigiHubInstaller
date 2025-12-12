Digital Hub for ham radio (DigiHub)

DigiHub is designed to be an alternative to the popular DigiPi which is an excellent implementation (but has limitations) and, is highly recommended as a starting point for the less tech savvy or those setting out on the digital ham path.

DigiHub, builds on the DigiPi concept and is designed to be installed on an existing Debian system. The installation script has been built and tested on Debian trixie 64-bit meaning it can be installed on Raspberry Pi OS (Pi Zero 2W, 3, 4 or, 5).

The primary benefit of DigiHub is it's flexibily and configurability. (list)

GPS Devices

DigiHub will detect and use a correctly installed and working GPS device.

can be installed for and individual or club callsign


DigiHub webserver

A number of the methods used to install, run and maintain DigiHub have been made into command line utilities:
aprspass    -   Generate your APRS password (bash/python)
checkcall   -   Check a callsign using the hamdb API (bash)
dwsetup     -   Install, or update and existing installation of, Direwolf (bash)
hamgrid     -   Get you Maidenhead ham grid from latitude and longitude (bash/python)
sysinfo     -   System information (bash)
These along with other useful tools are located in DigiHub/scripts (included in the PATH after install).

All software is open-source licensed and is freely available.

Credits:
DigiPi    https://digipi.org
Direwolf  https://github.com/wb2osz/direwolf
hamdb     https://hamdb.org

Installation instructions

sudo apt install git
git clone <DigiHub repository>
cd <Install Folder>
chmod +x install.sh <callsign> e.g. ./install.sh kq4zciy
./install.sh

either reboot (script option)
source ~/.profile
