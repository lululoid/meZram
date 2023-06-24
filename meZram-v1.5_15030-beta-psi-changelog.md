__v1.5-beta-psi__
    - add --switch to aggressive mode
    - service optimization
    - add wmemswap for monitoring purposes
    - overall optimization
    - [GOOD ONE]custom lmk props per app. Set it on /data/adb/meZram/meZram.conf. Increase performace, reduce lag. Tested on Redmi 10C, tested on Ace Racer, with this module I was able to use ultra graphic on 30-ish fps. Example included in "man" folder in the module. 

__v1.3-beta-psi__
- *high performance*
    - ro.lmk.thrashing_limit=50

- __universal__
    - Add Indonesian for help page
    - Adding Aggressive Mode. Access it from terminal using "agmode --help" command
    - remove most of props tweak, now it's google default
    - ro.lmk.downgrade_pressure=55. All you need is this prop, other props is just downright mistery to me nor I have courage to learn C. I just know from trial and error.
