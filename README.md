[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Documentation Status](https://readthedocs.org/projects/core-v-mcu/badge/?version=latest)](https://core-v-mcu.readthedocs.io/en/latest/?badge=latest)

# CORE-V MCU

> This a fork of the OpenHW Group CORE-V MCU repo.
>
> This repo includes FPGA support for a cv32e40p core extended with a vector AI accelerator

## Getting Started

Install the required Python tools:

```
pip3 install --user -r python-requirements.txt
```

Install fusesoc: https://fusesoc.readthedocs.io/en/stable/user/installation.html#ug-installation

## Building
To build the bitstream for Nexys A7-100T

$ make nexys-emul

To download the bitstream, connect your PC can to the Digilent USB-JTAG (portJ6, labeled “PROG”), power the board on, then type:

$ make download0

##Debugging

1- Download openocd 0.11-rc2 and add it to your PATH

https://sourceforge.net/projects/openocd/files/openocd/

2- Download and install the risc-v vector support toolchain, add the binaries to your PATH. Scripts for setting this up are provided in the toolchain-setup folder

3-Create an exectuable file for testing on the board. Sample programs as well as the linker script link.ld are given in the programs folder. We take hello-world.c as an example: 

riscv32-corev-elf-gcc -Os -g -fno-jump-tables -mabi=ilp32 -march=rv32imcv -c -o hello-world.o hello-world.c

riscv32-corev-elf-gcc -Tlink.ld -o hello-world.elf hello-world.o 

4- Connect the Digilent hs2 to pmod at the lower pins of JB. Switch SW0 to ON position (towards the board)

5- Connect to openocd using the config file openocd-nexys-hs2.cfg: 
$ sudo openocd -f openocd-nexys-hs2.cfg

5- On another terminal window, start gdb

$ riscv32-corev-elf-gdb hello-world.elf

You should see the following output:

GNU gdb ('corev-openhw-gcc-ubuntu1804-20200913') 10.0.50.20200818-git

Copyright (C) 2020 Free Software Foundation, Inc.

License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>

This is free software: you are free to change and redistribute it.

There is NO WARRANTY, to the extent permitted by law.

Type "show copying" and "show warranty" for details.

This GDB was configured as "--host=x86_64-pc-linux-gnu --target=riscv32-corev-elf".

Type "show configuration" for configuration details.

For bug reporting instructions, please see:

<'https://www.embecosm.com'>.
Find the GDB manual and other documentation resources online at:
    <http://www.gnu.org/software/gdb/documentation/>.


For help, type "help".

Type "apropos word" to search for commands related to "word"...

Reading symbols from hello-world.elf...

(gdb)



5.2 Inside gdb, connect to openocd on port 3333

target extended-remote :3333

gdb should respond with the following:

Remote debugging using :3333

0x1c000000 in _start ()

(gdb)


5.3 Load the program

(gdb) load

10.4 To continue execution, type 
(gdb) continue
