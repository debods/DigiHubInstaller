Digital Hub for ham radio - DigiHub
===================================
Overview
--------
DigiHub is not an application or environment, it is a curated collection of ham radio utilities and applications geared toward Digital Operation.
It is designed to be an alternative to the popular DigiPi which is an excellent implementation (but has limitations) and, is a highly recommended option for those setting out on the digital ham path.
DigiHub, builds on the DigiPi concept and unlike DigiPi is designed to be installed on an existing Debian system.
The installation script has been built and tested on Debian trixie 64-bit meaning it can be installed on Raspberry Pi OS running on a Pi Zero 2W, 3, 4 or, 5.

The primary benefit of DigiHub is it's flexibily and configurability. (list)


Note to Non US users
DigiHub leverages an API for callsigns and user data which in the US is reliable, unfortunately outside the US this is not the case. 
To enable users outside the US to use DigiHub, entering non-us (or NON-US) as the callsign (e.g. ./install.sh NON-US) when installing DigiHub will allow manual entry of the unvalidated callsign.



GPS Devices
DigiHub will detect and use correctly installed and working GPS devices.
A recommended GPS device is a Waveshare L76X Multi-GNSS HAT, it works with any PC hardware via USB, and Raspberry Pi via the GPIO header.



can be installed for an individual or club callsign


DigiHub webserver

A number of the methods used to install, run and maintain DigiHub have been made into command line utilities:
aprspass    -   Generate an APRS password (bash/python)
checkcall   -   Check a US callsign using the hamdb API (bash)
dwsetup     -   Install, or update an existing installation of, Direwolf (bash)
hamgrid     -   Calculate a Maidenhead ham grid from latitude and longitude (bash/python)
sysinfo     -   System information (bash)

These along with other useful tools are located in DigiHub/scripts (included in the PATH after install).

All software is open-source licensed and is freely available.

Credits:
DigiPi    https://digipi.org
Direwolf  https://github.com/wb2osz/direwolf
hamdb     https://hamdb.org

Installation instructions:

Ensure the Operating System you are installing on has an active Internet connection, then issue the following commands:

If necessary, as it may already be installed:

sudo apt install git

Clone the repository:

git clone <DigiHub repository>

Change directory to the install folder and make the installer executable:

cd <Install Folder>
chmod +x install.sh

Run the installer

./install.sh <callsign> (e.g. ./install.sh kq4zci or ./install.sh non-us)
