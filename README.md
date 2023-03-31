# Hi this is my first module
Change ZRAM size and SWAP size, applying lmkd psi. Change SWAP size up to RAM size.
  - Default size for both is 50% of RAM size.

## What is lmkd
The Android low memory killer daemon (lmkd) process monitors the memory state of a running Android system and reacts to high memory pressure by killing the least essential processes to keep the system performing at acceptable levels. These module use latest technique called "PSI monitors" because the vmpressure signals (generated by the kernel for memory pressure detection and used by lmkd) often include numerous false positives, lmkd must perform filtering to determine if the memory is under real pressure. This results in unnecessary lmkd wakeups and the use of additional computational resources. Using PSI monitors results in more accurate memory pressure detection and minimizes filtering overhead.
Details in here https://source.android.com/docs/core/perf/lmkd 

## Features
  - lmkd tweaks for smoother experience.
  - open more apps, while also maintaining performance
  - may increase gaming performance by reducing pressure aspects, especially memory pressure
  - tweak the props on you own by tweaking /data/adb/modules/meZram/system.prop then restart. Be careful because this modify low level system. Could break your system although it isn't permanent, just reinstall or remove this module if it happened.
  - change ZRAM size
  - change SWAP size (customizable)
  - adjusting SWAP size on your own. Up to the size of your RAM. Although i don't recommmend it for general user because it's more likely has no performance benefits. The default 50% is enough.

## TODO
- Fix killer bug. After a while device will enter a state where it couldn't clear memory until it reached its maximal capacity, as you could expect this resulting in system killing apps leaving only 2 user apps left open. I think the problem is on psi_monitor which is written in C++ 🥲.
- Add AI? lol 😹. Seriously its's never better. While demands changing based on user, the tweaks itself become less efficient. Add AI that could adapt to user seems to be interesting idea. But I still have so much to learn, anxiety and depression is the biggest obstacle of mine.

## DEBUG
- Tested on Redmi 10C RiceDroid 10.2 Gapps
- Realme 5 Android 10
