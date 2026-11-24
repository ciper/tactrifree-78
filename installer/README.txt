tactrifree 78 1.0 beta7 - for Windows 7, 8 and 8.1
==================================================
Open-source J2534 driver for the OpenPort 2.0 cable, for J2534 programs
(RomRaider, FastECU, ...). Windows 7, 8 and 8.1, 32-bit or 64-bit.
On Windows 10 and 11 use the normal tactrifree package instead.
Not affiliated with or endorsed by Tactrix.

If anything goes wrong, the setup window stays open and shows what failed:
please report it on the project's GitHub page with a screenshot of the whole
window, or the log file it names.

NOT INCLUDED: EcuFlash support. EcuFlash keeps using the original Tactrix
driver, so while tactrifree is installed EcuFlash does not see the cable.
To use EcuFlash again: uninstall tactrifree, then unplug and replug the cable.

INSTALL
1. Close RomRaider, FastECU and EcuFlash.
2. Plug the OpenPort 2.0 cable into USB (the car is not needed).
3. Unzip this folder anywhere, then double-click "installer.cmd" and click
   Yes when Windows asks for administrator permission.
4. Wait for "Setup finished OK." and press a key.
5. In RomRaider / FastECU choose "TactriFree J2534 for OpenPort 2.0".

To only see what setup would do, without changing anything: open a command
prompt in this folder and run
   powershell -ExecutionPolicy Bypass -File TactriFree-Setup.ps1 -Plan

UNINSTALL
Control Panel > Programs and Features > TactriFree > Uninstall (or double-click
"Uninstall TactriFree.cmd"), then unplug and replug the cable.

LOGS (send these when reporting a problem)
  C:\Program Files\TactriFree\setup.log  (or %TEMP%\tactrifree-setup.log if setup failed early)
  %TEMP%\tactrifree-debug.log            (the driver, while a program uses the cable)
