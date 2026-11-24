# tactrifree 78

TactriFree is a replacement driver setup for the OpenPort 2.0 that provides 32/64-bit J2534 interfaces. No ECUFlash support! 

Windows 10 and 11 should use the main version at https://github.com/ciper/tactrifree

Details:
- TactriFree doesn't actually install a "driver" of its own. The cable runs on WinUSB, the USB driver built into Windows and signed by Microsoft. What gets signed is TactriFree's small setup file that points the cable at WinUSB, and it's signed on the user's own PC during install. Setup creates a certificate for that one PC, signs with it, then deletes the signing key so the certificate can never sign anything else. The J2534 DLLs and the EcuFlash DLL themselves aren't signed.



