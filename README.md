# Hi this is my first module
Add ZRAM and swap to your android. It works by change default ZRAM size and add swap, both size to 1/2 of RAM.
So you'll add virtual memory as much as your RAM meaning if RAM is 4 GB there will be (2GB ZRAM + 2GB SWAP).
You could also change SWAP size on your own.

## Features
  - lmkd tweaks for smoother experience. Based on https://source.android.com/docs/core/perf/lmkd.
  - change the size of your SWAP
  - change the size of your ZRAM

## TODO
