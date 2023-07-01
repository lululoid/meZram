# Hi this is my first module

# What this module do?

To enhance multitasking performance, transition to a more advanced memory management system known as LMKD, which stands for low memory killer daemon but also use PSI (Pressure stall information) which basically better for performance stability. By installing this module, the system gains additional capabilities such as SWAP and adjusts the ZRAM configuration to occupy half of the total RAM capacity. These modifications aim to optimize memory utilization and improve the efficiency of concurrent task execution.

## What is lmkd

The Android low memory killer daemon (lmkd) process monitors the memory state of a running Android system and reacts to high memory pressure by killing the least essential processes to keep the system performing at acceptable levels. These module use latest technique called "PSI monitors" because the vmpressure signals (generated by the kernel for memory pressure detection and used by lmkd) often include numerous false positives, lmkd must perform filtering to determine if the memory is under real pressure. This results in unnecessary lmkd wakeups and the use of additional computational resources. Using PSI monitors results in more accurate memory pressure detection and minimizes filtering overhead.
Details in here https://source.android.com/docs/core/perf/lmkd

## Features

- 😾 Aggressive Mode

<pre style="max-width: 100%; overflow-x: scroll;">Usage: agmode [-OPTION] or OPTIONS...</pre>

MANUAL FOR AGGRESSIVE MODE MEZRAM module

- ⚠️==WARNING==⚠️
  While it is technically possible to set the "downgrade_pressure" value as high as 100, it's important to understand that going beyond the territory of 80 can be risky and may lead to performance instability.

You can use the following commands/options for managing this feature:

<pre style="max-width: 100%; overflow-x: scroll;">-g | --get        Print LMKD properties
--enable               Enabling aggressive mode 
--disable              Disabling aggressive mode 
--log [line number]    Show log.
--show                 Showing config
--reload               Reload custom props then reapply
--help | -h [language] Show this help.
	--help id            Untuk menampilkan bantuan dalam bahasa Indonesia.
--rmswap               Remove SWAP from this module. Reinstall module to make new SWAP.
--switch               Switch LMKD mode. There's two mode, psi and the other one is minfree_levels which is older and less advanced mode.
--wait-time [number]   Wait time before exiting agmode after application closed. The reason is to prevent lag and apps being killed. Fill the number with 1m for 1 minute, it could also be 30 for 30 seconds. 

downgrade_pressure=[value] Change ro.lmk.downgrade_pressure prop value. Value is between 0-100.
"⚠️!!! Beware not to set more than 80 in minfree_levels mode. It will break you device !!!"
</pre>
<img src="https://github.com/lululoid/meZram/blob/psi_variant/pic/wmemswap.jpg" height="500"/>

- Use LMKD PSI aims to provide a smoother user experience.
- The enhanced memory management allows for the concurrent execution of more applications while maintaining performance.
- By reducing memory pressure, particularly in gaming scenarios, there is a potential improvement in gaming performance.
- Advanced users can manually tweak system properties by modifying the /data/adb/modules/meZram/system.prop file and then restarting the system. It is important to exercise caution as these modifications affect low-level system components. In case of any issues, the module can be reinstalled or removed to restore system functionality.
- The ZRAM size can be modified to allocate a different portion of the RAM for compressed memory storage.
- The SWAP size is customizable, enabling adjustment according to specific requirements.
- It is possible to fine-tune the SWAP size up to the total RAM capacity, but this is generally not recommended for general users as it may not provide significant performance benefits. The default 50% allocation is typically sufficient.
- wmemswap command for monitoring
  <img src="https://github.com/lululoid/meZram/blob/psi_variant/pic/wmemswap.jpg"/>

## CONFIGURATION
Need to add some config example here later

## TODO

- How about adding some AI magic? LOL! 😹 Seriously though, things are getting wild! As user demands keep changing, the traditional tweaks just can't keep up. But hey, why not introduce some AI into the mix? Imagine an AI that can adapt to each user's unique needs. Now that's an intriguing idea! But hey, don't mind me, I'm just an rookie myself, and there's still so much for me to learn! 📚

## DEBUG

- Tested on Redmi 10C MIUI 13
- Realme 5 Android 10
